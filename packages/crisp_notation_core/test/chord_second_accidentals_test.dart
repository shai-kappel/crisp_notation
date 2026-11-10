import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// R11 and R7: a stemless chord with a second places the displaced head on
/// the reference's side, and its accidentals stand left of every head in a
/// staggered stack that touches neither each other nor the heads.
///
/// The shape is the corpus's `chord-4-notes-double-flat`: the whole-note
/// chord G4, A𝄫4, C5, E♭5 (abcjs `[G__Ac_e]4`). Its farther extreme (E♭5)
/// is above the middle line, so its stem direction is down; the lower note of
/// the second (G4) goes left of the upper (A𝄫4), as abcjs draws it. The
/// accidental column order follows the owner's ruling U1 ("Match abcjs"): the
/// lowest accidental takes the column nearest the chord, so 𝄫 sits nearest
/// and ♭ outside it.
late final SmuflMetadata metadata;
late final LayoutSettings settings;

const _eps = 1e-9;

ScoreLayout _layout(String notes) =>
    const LayoutEngine().layout(Score.simple(notes: notes), settings);

/// A glyph's ink box on the page (SMuFL boxes are y-up; the page is y-down).
Rectangle<double> _box(GlyphPrimitive g) {
  final b = metadata.bBoxOf(g.smuflName);
  return Rectangle.fromPoints(
    Point(g.position.x + b.swX * g.scale, g.position.y - b.neY * g.scale),
    Point(g.position.x + b.neX * g.scale, g.position.y - b.swY * g.scale),
  );
}

/// The element's noteheads, lowest pitch first (largest page y first).
List<GlyphPrimitive> _heads(ScoreLayout layout) => layout.primitives
    .whereType<GlyphPrimitive>()
    .where((g) => g.smuflName.startsWith('notehead') && g.elementId != null)
    .toList()
  ..sort((a, b) => b.position.y.compareTo(a.position.y));

/// The element's accidental glyphs, lowest pitch first.
List<GlyphPrimitive> _accidentals(ScoreLayout layout) => layout.primitives
    .whereType<GlyphPrimitive>()
    .where((g) => g.smuflName.startsWith('accidental') && g.elementId != null)
    .toList()
  ..sort((a, b) => b.position.y.compareTo(a.position.y));

bool _overlap(Rectangle<double> a, Rectangle<double> b) =>
    a.left < b.right - _eps &&
    b.left < a.right - _eps &&
    a.top < b.bottom - _eps &&
    b.top < a.bottom - _eps;

String _geometry(ScoreLayout layout) => [
      for (final g in [..._heads(layout), ..._accidentals(layout)])
        '${g.smuflName}@${g.position.x.toStringAsFixed(6)},'
            '${g.position.y.toStringAsFixed(6)}',
    ].join(' ');

void main() {
  setUpAll(() {
    final source = File('../crisp_notation/assets/smufl/bravura_metadata.json')
        .readAsStringSync();
    metadata =
        SmuflMetadata.fromJson(jsonDecode(source) as Map<String, Object?>);
    settings = LayoutSettings(metadata: metadata);
  });

  group('chord-4-notes-double-flat (g4+abb4+c5+eb5:w)', () {
    late ScoreLayout layout;
    late List<GlyphPrimitive> heads;
    late List<GlyphPrimitive> accidentals;

    setUp(() {
      layout = _layout('g4+abb4+c5+eb5:w');
      heads = _heads(layout);
      accidentals = _accidentals(layout);
    });

    test('has four heads and the double flat and the flat', () {
      expect(heads, hasLength(4));
      expect(
        accidentals.map((g) => g.smuflName),
        ['accidentalDoubleFlat', 'accidentalFlat'],
      );
    });

    test('R11: the lower note of the second (G4) sits left of A𝄫4', () {
      final g4 = heads[0], a4 = heads[1];
      expect(g4.position.x, lessThan(a4.position.x - _eps));
      // Side by side, not overlapping: G's head ends where A's begins.
      expect(_box(g4).right, lessThanOrEqualTo(_box(a4).left + 0.2));
      // A𝄫4, C5 and E♭5 share the chord's column.
      expect(heads[2].position.x, closeTo(a4.position.x, _eps));
      expect(heads[3].position.x, closeTo(a4.position.x, _eps));
    });

    test('R7: every accidental box lies left of the leftmost head', () {
      final leftmost = heads.map((h) => _box(h).left).reduce(min);
      for (final a in accidentals) {
        expect(
          _box(a).right,
          lessThanOrEqualTo(leftmost - settings.accidentalGap + 1e-6),
          reason: '${a.smuflName} reaches into the heads',
        );
        for (final h in heads) {
          expect(
            _overlap(_box(a), _box(h)),
            isFalse,
            reason: '${a.smuflName} touches ${h.smuflName}',
          );
        }
      }
    });

    test('R7: the double flat and the flat do not overlap', () {
      expect(_overlap(_box(accidentals[0]), _box(accidentals[1])), isFalse);
    });

    test('R7 (U1): the double flat is nearest the chord, the flat outside',
        () {
      final doubleFlat = accidentals[0], flat = accidentals[1];
      expect(doubleFlat.smuflName, 'accidentalDoubleFlat');
      expect(flat.smuflName, 'accidentalFlat');
      // A staggered stack: two columns, the flat entirely left of the 𝄫.
      expect(_box(flat).right, lessThan(_box(doubleFlat).left + _eps));
    });
  });

  // Stem-up stemless chords with a second keep the geometry they had at
  // 535b315f: the upper note of the second goes right, and the accidentals
  // stand left of the chord's column. Values recorded from 535b315f.
  test('stem-up f4+g##4+c5:w keeps its notehead and accidental geometry', () {
    expect(
      _geometry(_layout('f4+g##4+c5:w')),
      'noteheadWhole@5.922000,3.500000 noteheadWhole@7.610000,3.000000 '
      'noteheadWhole@5.922000,1.500000 '
      'accidentalDoubleSharp@4.684000,3.000000',
    );
  });

  test('13_chord_seconds b3+c4+d4:w keeps its notehead geometry', () {
    expect(
      _geometry(_layout('b3+c4+d4:w')),
      'noteheadWhole@4.684000,5.500000 noteheadWhole@6.372000,5.000000 '
      'noteheadWhole@4.684000,4.500000',
    );
  });
}
