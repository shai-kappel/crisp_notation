import 'dart:convert';
import 'dart:io';

import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// R10: a tuplet bracket is drawn only on a group that is not beamed; a fully
/// beamed group gets its number (2, 3, 5) and no bracket.
late final SmuflMetadata metadata;
late final LayoutSettings settings;

ScoreLayout layoutOf(Score score) =>
    const LayoutEngine().layout(score, settings);

/// One tuplet group as drawn: its digit glyph(s) and whether bracket lines
/// sit beside them.
typedef DrawnTuplet = ({String digit, bool bracket});

/// Every tuplet digit in [layout], left to right, with the bracket presence
/// beside it. A bracket is two horizontal segments of
/// `tupletBracketThickness` either side of the digit on the line the digit
/// is centred on (`digit.y - 0.75`), plus two hooks.
List<DrawnTuplet> tupletsOf(ScoreLayout layout) {
  final thickness =
      metadata.engravingDefault('tupletBracketThickness', orElse: 0.16);
  final lines = layout.primitives
      .whereType<LinePrimitive>()
      .where((l) =>
          l.thickness == thickness &&
          l.elementId == null &&
          !(l.from.y == 0 && l.to.y == 4) &&
          !(l.from.y == l.to.y && l.from.x == 0))
      .toList();
  final horizontals = lines.where((l) => l.from.y == l.to.y).toList();
  final digits = layout.primitives
      .whereType<GlyphPrimitive>()
      .where((g) => g.smuflName.startsWith('tuplet'))
      .toList()
    ..sort((a, b) => a.position.x.compareTo(b.position.x));
  return [
    for (final d in digits)
      (
        digit: d.smuflName,
        bracket: horizontals.any((l) =>
            (l.from.y - (d.position.y - 0.75)).abs() < 1e-9 &&
            d.position.x - l.to.x > 0 &&
            d.position.x - l.to.x < 2.5),
      ),
  ];
}

/// The number of bracket hooks (vertical bracket-thickness lines off the
/// staff) in [layout].
int hookCount(ScoreLayout layout) {
  final thickness =
      metadata.engravingDefault('tupletBracketThickness', orElse: 0.16);
  return layout.primitives
      .whereType<LinePrimitive>()
      .where((l) =>
          l.thickness == thickness &&
          l.elementId == null &&
          l.from.x == l.to.x &&
          !(l.from.y == 0 && l.to.y == 4))
      .length;
}

NoteElement note(String step, int octave, NoteDuration d, String id) =>
    NoteElement(
        pitches: [Pitch(Step.values.byName(step), octave: octave)],
        duration: d,
        id: id);

void main() {
  setUpAll(() {
    final source = File('../crisp_notation/assets/smufl/bravura_metadata.json')
        .readAsStringSync();
    metadata =
        SmuflMetadata.fromJson(jsonDecode(source) as Map<String, Object?>);
    settings = LayoutSettings(metadata: metadata);
  });

  group('R10 row shapes', () {
    test('duplet: beamed 2:3 eighth pairs have no bracket, an unbeamed '
        '2:3 quarter pair has one', () {
      // abcjs: (2ce (2dB | (2c2A2 |]  in 6/8.
      final layout = layoutOf(Score.simple(
        timeSignature: const TimeSignature(6, 8),
        notes: '2[c5:e e5] 2[d5:e b4] | 2[c5:q a4:q]',
      ));
      expect(tupletsOf(layout), [
        (digit: 'tuplet2', bracket: false),
        (digit: 'tuplet2', bracket: false),
        (digit: 'tuplet2', bracket: true),
      ]);
      expect(hookCount(layout), 2);
    });

    test('triplet: beamed eighth triplets have no bracket, an unbeamed '
        'quarter triplet has one', () {
      // abcjs: (3cde (3fed | (3c2B2A2 |]  in 2/4.
      final layout = layoutOf(Score.simple(
        timeSignature: const TimeSignature(2, 4),
        notes: '3[c5:e d5 e5] 3[f5:e e5 d5] | 3[c5:q b4 a4]',
      ));
      expect(tupletsOf(layout), [
        (digit: 'tuplet3', bracket: false),
        (digit: 'tuplet3', bracket: false),
        (digit: 'tuplet3', bracket: true),
      ]);
      expect(hookCount(layout), 2);
    });

    test('quintuplet: a beamed sixteenth 5:4 and a beamed eighth 5:4 have '
        'no bracket', () {
      // abcjs: (5:4:5cdefg a4 | (5:4:5g2f2e2d2c2 |]  in 2/4, L:1/16.
      final layout = layoutOf(Score.simple(
        timeSignature: const TimeSignature(2, 4),
        notes: '5:4[c5:s d5 e5 f5 g5] a5:q | 5:4[g5:e f5 e5 d5 c5]',
      ));
      expect(layout.primitives.whereType<BeamPrimitive>(), isNotEmpty);
      expect(tupletsOf(layout), [
        (digit: 'tuplet5', bracket: false),
        (digit: 'tuplet5', bracket: false),
      ]);
      expect(hookCount(layout), 0);
    });
  });

  group('R10 edge cases', () {
    test('an inner rest: the beam skips the rest, so no bracket', () {
      final layout = layoutOf(Score.simple(
        timeSignature: const TimeSignature(2, 4),
        notes: '3[c5:e r e5] c5:q',
      ));
      expect(layout.primitives.whereType<BeamPrimitive>(), hasLength(1));
      expect(tupletsOf(layout), [(digit: 'tuplet3', bracket: false)]);
      expect(hookCount(layout), 0);
    });

    test('a span starting on a rest keeps its bracket', () {
      final layout = layoutOf(Score.simple(
        timeSignature: const TimeSignature(2, 4),
        notes: '3[r:e d5 e5] c5:q',
      ));
      expect(layout.primitives.whereType<BeamPrimitive>(), hasLength(1));
      expect(tupletsOf(layout), [(digit: 'tuplet3', bracket: true)]);
      expect(hookCount(layout), 2);
    });

    test('a span ending on a rest keeps its bracket', () {
      final layout = layoutOf(Score.simple(
        timeSignature: const TimeSignature(2, 4),
        notes: '3[c5:e d5 r] c5:q',
      ));
      expect(tupletsOf(layout), [(digit: 'tuplet3', bracket: true)]);
    });

    test('a span split across two beam groups keeps its bracket', () {
      // Six eighths in the time of four (a half note) in 4/4, the source
      // stating two beams over it (3 + 3): no one drawn beam covers the span.
      final layout = layoutOf(Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: '6:4[c5:e d5 e5 f5 e5 d5] c5:h',
      ).copyWith(
        beamsExplicit: true,
        beamSpans: const [BeamSpan('e0', 'e2'), BeamSpan('e3', 'e5')],
      ));
      expect(layout.primitives.whereType<BeamPrimitive>(), hasLength(2),
          reason: 'the span is split across two beam groups');
      expect(tupletsOf(layout), [(digit: 'tuplet6', bracket: true)]);
      expect(hookCount(layout), 2);
    });

    test('quintuplet bar 2: five eighths 5:4 in 2/4 are one beam across '
        'both beats, digit 5, no bracket', () {
      final layout = layoutOf(Score.simple(
        timeSignature: const TimeSignature(2, 4),
        notes: '5:4[g5:e f5 e5 d5 c5]',
      ));
      expect(layout.primitives.whereType<BeamPrimitive>(), hasLength(1));
      expect(tupletsOf(layout), [(digit: 'tuplet5', bracket: false)]);
      expect(hookCount(layout), 0);
    });

    test('a beamable tuplet crossing a beat boundary is one beam, no bracket',
        () {
      // In 4/4 the triplet starts on the "and" of beat 1 and ends inside
      // beat 2; the eighths either side keep their flags.
      final layout = layoutOf(Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: 'c5:e 3[d5:e e5 f5] g5:e c5:h',
      ));
      expect(layout.primitives.whereType<BeamPrimitive>(), hasLength(1));
      expect(tupletsOf(layout), [(digit: 'tuplet3', bracket: false)]);
      expect(hookCount(layout), 0);
    });

    test('six eighths 6:4 under meter beaming become one beam', () {
      final layout = layoutOf(Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: '6:4[c5:e d5 e5 f5 e5 d5] c5:h',
      ));
      expect(layout.primitives.whereType<BeamPrimitive>(), hasLength(1));
      expect(tupletsOf(layout), [(digit: 'tuplet6', bracket: false)]);
    });

    test('a voice-1 beamed tuplet in a multi-voice measure keeps its bracket',
        () {
      final layout = layoutOf(Score(
        clef: Clef.treble,
        timeSignature: const TimeSignature(2, 4),
        measures: [
          Measure(
            [
              note('c', 5, NoteDuration.eighth, 'a1'),
              note('d', 5, NoteDuration.eighth, 'a2'),
              note('e', 5, NoteDuration.eighth, 'a3'),
              note('f', 5, NoteDuration.quarter, 'a4'),
            ],
            voice2: [
              note('e', 4, NoteDuration.half, 'b1'),
            ],
            tuplets: const [TupletSpan(0, 2, actual: 3, normal: 2)],
          ),
        ],
      ));
      expect(layout.primitives.whereType<BeamPrimitive>(), isNotEmpty);
      expect(tupletsOf(layout), [(digit: 'tuplet3', bracket: true)]);
      expect(hookCount(layout), 2);
    });

    test('an inner-voice beamed tuplet keeps its bracket', () {
      final layout = layoutOf(Score(
        clef: Clef.treble,
        timeSignature: const TimeSignature(2, 4),
        measures: [
          Measure(
            [
              note('c', 5, NoteDuration.half, 'a1'),
            ],
            voice2: [
              note('e', 4, NoteDuration.eighth, 'b1'),
              note('f', 4, NoteDuration.eighth, 'b2'),
              note('g', 4, NoteDuration.eighth, 'b3'),
              note('a', 4, NoteDuration.quarter, 'b4'),
            ],
            tuplets: const [TupletSpan(0, 2, actual: 3, normal: 2, voice: 1)],
          ),
        ],
      ));
      expect(layout.primitives.whereType<BeamPrimitive>(), isNotEmpty);
      expect(tupletsOf(layout), [(digit: 'tuplet3', bracket: true)]);
      expect(hookCount(layout), 2);
    });
  });
}
