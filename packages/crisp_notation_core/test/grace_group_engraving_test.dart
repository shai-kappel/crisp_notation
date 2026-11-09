import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// R12: grace groups are drawn small; a group of two or more is beamed; an
/// acciaccatura has a slash through the single grace's stem and flag, or the
/// first stem and beam of a beamed group; an appoggiatura has none; and a
/// grace slur joins the grace note(s) to the principal, for both styles.
///
/// The shapes are the corpus's: a single D5 before C5, then F4–G4 before A4
/// (abcjs `{/d}c2 {/FG}A2` and `{d}c2 {FG}A2`).
late final SmuflMetadata metadata;
late final LayoutSettings settings;

const _scale = 0.6;
const _eps = 1e-9;

const _c5 = Pitch(Step.c, octave: 5);
const _d5 = Pitch(Step.d, octave: 5);
const _f4 = Pitch(Step.f, octave: 4);
const _g4 = Pitch(Step.g, octave: 4);
const _a4 = Pitch(Step.a, octave: 4);

/// The corpus fragment in [style]: `a` = {D5}C5, `b` = {F4 G4}A4.
Score _corpus(GraceStyle style) => Score(
      clef: Clef.treble,
      measures: [
        Measure([
          NoteElement.note(
            _c5,
            NoteDuration.half,
            graceNotes: const [_d5],
            graceStyle: style,
            id: 'a',
          ),
          NoteElement.note(
            _a4,
            NoteDuration.half,
            graceNotes: const [_f4, _g4],
            graceStyle: style,
            id: 'b',
          ),
        ]),
      ],
    );

ScoreLayout _layout(Score score) =>
    const LayoutEngine().layout(score, settings);

/// A glyph's ink box on the page (SMuFL boxes are y-up; the page is y-down).
Rectangle<double> _box(GlyphPrimitive g) {
  final b = metadata.bBoxOf(g.smuflName);
  return Rectangle.fromPoints(
    Point(g.position.x + b.swX * g.scale, g.position.y - b.neY * g.scale),
    Point(g.position.x + b.neX * g.scale, g.position.y - b.swY * g.scale),
  );
}

bool _overlaps(Rectangle<double> a, Rectangle<double> b) =>
    a.left < b.right - 1e-6 &&
    b.left < a.right - 1e-6 &&
    a.top < b.bottom - 1e-6 &&
    b.top < a.bottom - 1e-6;

/// One graced note's ink, split into its graces and its principal.
class _Graced {
  final ScoreLayout layout;
  final String id;
  _Graced(this.layout, this.id);

  Iterable<LayoutPrimitive> get _own =>
      layout.primitives.where((p) => p.elementId == id);

  GlyphPrimitive get principalHead =>
      _own.whereType<GlyphPrimitive>().singleWhere(
            (g) =>
                g.scale == 1.0 &&
                (g.smuflName == SmuflGlyph.noteheadBlack ||
                    g.smuflName == SmuflGlyph.noteheadHalf),
          );

  List<GlyphPrimitive> get graceGlyphs =>
      _own.whereType<GlyphPrimitive>().where((g) => g.scale != 1.0).toList();

  List<GlyphPrimitive> get graceHeads =>
      graceGlyphs.where((g) => g.smuflName == SmuflGlyph.noteheadBlack).toList()
        ..sort((a, b) => a.position.x.compareTo(b.position.x));

  List<GlyphPrimitive> get graceFlags =>
      graceGlyphs.where((g) => g.smuflName.startsWith('flag')).toList();

  /// Vertical lines left of the principal head of stem thickness: the grace
  /// stems, left to right.
  List<LinePrimitive> get graceStems => _own
      .whereType<LinePrimitive>()
      .where(
        (l) =>
            l.from.x == l.to.x &&
            l.from.x < principalHead.position.x &&
            l.thickness == settings.stemThickness,
      )
      .toList()
    ..sort((a, b) => a.from.x.compareTo(b.from.x));

  /// The principal's stem: the vertical stem-thick line right of its head's
  /// left edge.
  LinePrimitive get principalStem =>
      _own.whereType<LinePrimitive>().singleWhere(
            (l) =>
                l.from.x == l.to.x &&
                l.from.x >= principalHead.position.x &&
                l.thickness == settings.stemThickness,
          );

  /// Diagonal lines carrying the element's id: the slash (stems, ledgers
  /// and the principal's stem are axis-aligned).
  List<LinePrimitive> get slashes => _own
      .whereType<LinePrimitive>()
      .where((l) => l.from.x != l.to.x && l.from.y != l.to.y)
      .toList();

  List<BeamPrimitive> get graceBeams => layout.primitives
      .whereType<BeamPrimitive>()
      .where(
        (b) =>
            b.end.x <= principalHead.position.x &&
            b.start.x >= graceHeads.first.position.x - 0.5,
      )
      .toList();

  /// Curves from (under) the first grace head to the principal head.
  List<CurvePrimitive> get graceSlurs {
    final first = _box(graceHeads.first);
    final head = _box(principalHead);
    return layout.primitives.whereType<CurvePrimitive>().where((c) {
      final startsAtGrace = c.start.x >= first.left - _eps &&
          c.start.x <= first.right + _eps &&
          (c.start.y - first.top - first.height / 2).abs() <= 1.0;
      final endsAtPrincipal = c.end.x >= head.left - 0.5 &&
          c.end.x <= head.right + 0.5 &&
          (c.end.y - head.top - head.height / 2).abs() <= 1.0;
      return startsAtGrace && endsAtPrincipal;
    }).toList();
  }
}

/// Whether the segments p1–p2 and q1–q2 cross.
bool _segmentsCross(
  Point<double> p1,
  Point<double> p2,
  Point<double> q1,
  Point<double> q2,
) {
  double cross(Point<double> o, Point<double> a, Point<double> b) =>
      (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x);
  final d1 = cross(q1, q2, p1), d2 = cross(q1, q2, p2);
  final d3 = cross(p1, p2, q1), d4 = cross(p1, p2, q2);
  return d1 * d2 < 0 && d3 * d4 < 0;
}

/// Whether segment a–b passes through rectangle [r] (some sampled point of
/// it lies strictly inside).
bool _segmentEnters(Point<double> a, Point<double> b, Rectangle<double> r) {
  for (var i = 0; i <= 100; i++) {
    final t = i / 100;
    final x = a.x + (b.x - a.x) * t, y = a.y + (b.y - a.y) * t;
    if (x > r.left && x < r.right && y > r.top && y < r.bottom) return true;
  }
  return false;
}

void main() {
  setUpAll(() {
    final source = File(
      '../crisp_notation/assets/smufl/bravura_metadata.json',
    ).readAsStringSync();
    metadata = SmuflMetadata.fromJson(
      jsonDecode(source) as Map<String, Object?>,
    );
    settings = LayoutSettings(metadata: metadata);
  });

  for (final style in GraceStyle.values) {
    group('${style.name}: ', () {
      late ScoreLayout layout;
      late _Graced single, pair;
      setUp(() {
        layout = _layout(_corpus(style));
        single = _Graced(layout, 'a');
        pair = _Graced(layout, 'b');
      });

      test('grace notes are drawn small', () {
        for (final g in [single, pair]) {
          // Every grace glyph (heads, flags) at the 0.6 grace scale.
          expect(g.graceGlyphs, isNotEmpty);
          for (final glyph in g.graceGlyphs) {
            expect(glyph.scale, _scale);
          }
          // A grace stem is no longer than 0.6 x the principal's stem.
          final principal = g.principalStem;
          final principalLength = (principal.to.y - principal.from.y).abs();
          expect(g.graceStems, isNotEmpty);
          for (final stem in g.graceStems) {
            expect(
              (stem.to.y - stem.from.y).abs(),
              lessThanOrEqualTo(_scale * principalLength + _eps),
            );
          }
          // No grace glyph's box meets another grace's head or the
          // principal's head. A glyph belongs to the grace whose head is the
          // last one at or left of it (a flag hangs from its own stem).
          final heads = g.graceHeads;
          for (final glyph in g.graceGlyphs) {
            final own =
                heads.lastWhere((h) => h.position.x <= glyph.position.x);
            for (final head in [...heads, g.principalHead]) {
              if (identical(head, own)) continue;
              expect(
                _overlaps(_box(glyph), _box(head)),
                isFalse,
                reason: '${glyph.smuflName} at ${glyph.position} meets '
                    'the head at ${head.position}',
              );
            }
          }
        }
        // The grace beam's thickness is scaled too.
        expect(pair.graceBeams, hasLength(1));
        expect(
          pair.graceBeams.single.thickness,
          closeTo(settings.beamThickness * _scale, _eps),
        );
      });

      test('the single grace has a flag and no beam', () {
        expect(single.graceHeads, hasLength(1));
        expect(single.graceFlags.map((f) => f.smuflName), [
          SmuflGlyph.flag8thUp,
        ]);
        expect(single.graceBeams, isEmpty);
      });

      test('the two-note grace group is joined by a beam', () {
        expect(pair.graceHeads, hasLength(2));
        // Beamed graces carry no flags.
        expect(pair.graceFlags, isEmpty);
        final beam = pair.graceBeams.single;
        final stems = pair.graceStems;
        expect(stems, hasLength(2));
        // The beam spans both stems and meets each at its tip.
        expect(beam.start.x, lessThanOrEqualTo(stems.first.from.x));
        expect(beam.end.x, greaterThanOrEqualTo(stems.last.from.x));
        double beamYAt(double x) =>
            beam.start.y +
            (beam.end.y - beam.start.y) *
                (x - beam.start.x) /
                (beam.end.x - beam.start.x);
        for (final stem in stems) {
          final tip = min(stem.from.y, stem.to.y); // stems up
          expect(
            (tip - beamYAt(stem.from.x)).abs(),
            lessThanOrEqualTo(beam.thickness / 2 + _eps),
          );
        }
      });

      if (style == GraceStyle.acciaccatura) {
        test('a slash crosses the single grace\'s stem and flag', () {
          final slash = single.slashes.single;
          final stem = single.graceStems.single;
          expect(
            _segmentsCross(slash.from, slash.to, stem.from, stem.to),
            isTrue,
          );
          expect(
            _segmentEnters(
              slash.from,
              slash.to,
              _box(single.graceFlags.single),
            ),
            isTrue,
          );
        });

        test('a slash crosses the beamed group\'s first stem and beam', () {
          final slash = pair.slashes.single;
          final stems = pair.graceStems;
          expect(
            _segmentsCross(
              slash.from,
              slash.to,
              stems.first.from,
              stems.first.to,
            ),
            isTrue,
          );
          // It crosses the beam: from one side of the beam's body to the
          // other, within the beam's span.
          final beam = pair.graceBeams.single;
          final h = beam.thickness / 2;
          final upper1 = Point(beam.start.x, beam.start.y - h),
              upper2 = Point(beam.end.x, beam.end.y - h);
          final lower1 = Point(beam.start.x, beam.start.y + h),
              lower2 = Point(beam.end.x, beam.end.y + h);
          expect(_segmentsCross(slash.from, slash.to, upper1, upper2), isTrue);
          expect(_segmentsCross(slash.from, slash.to, lower1, lower2), isTrue);
        });
      } else {
        test('an appoggiatura has no slash', () {
          expect(single.slashes, isEmpty);
          expect(pair.slashes, isEmpty);
        });
      }

      test('a grace slur joins the grace note(s) to the main note', () {
        for (final g in [single, pair]) {
          final slurs = g.graceSlurs;
          expect(slurs, hasLength(1), reason: 'grace slur for ${g.id}');
          final slur = slurs.single;
          // Under the graces (their stems go up): it starts below the first
          // grace head's centre and ends just left of the principal head.
          expect(slur.start.y, greaterThan(g.graceHeads.first.position.y));
          expect(slur.end.x, lessThan(g.principalHead.position.x));
          expect(slur.start.x, lessThan(slur.end.x));
        }
      });
    });
  }

  group('two voices', () {
    // The same graced note object in a two-voice bar, then alone.
    const graced = NoteElement(
      pitches: [_c5],
      duration: NoteDuration.half,
      graceNotes: [_d5],
      id: 'g',
    );
    Score score() => Score(
          clef: Clef.treble,
          timeSignature: TimeSignature.fourFour,
          measures: [
            Measure(
              [graced, NoteElement.note(_c5, NoteDuration.half, id: 'u2')],
              voice2: [
                NoteElement.note(
                  _f4,
                  NoteDuration.half,
                  graceNotes: const [_g4],
                  id: 'l1',
                ),
                NoteElement.note(_f4, NoteDuration.half, id: 'l2'),
              ],
            ),
            Measure([
              NoteElement.note(_c5, NoteDuration.half, id: 'n1'),
              NoteElement.note(
                _a4,
                NoteDuration.half,
                graceNotes: const [_f4, _g4],
                id: 'n2',
              ),
            ]),
          ],
        );

    test('no grace slur is left pending or ends on an unrelated note', () {
      final layout = _layout(score());
      final curves = layout.primitives.whereType<CurvePrimitive>().toList();
      // The single-voice bar's graced note gets its own slur ...
      final n2 = _Graced(layout, 'n2');
      expect(n2.graceSlurs, hasLength(1));
      // ... and it is the only curve: the two-voice bar's graces leave no
      // slur behind to land on the next notes.
      expect(curves, hasLength(1));
      for (final id in ['u2', 'l2', 'n1']) {
        final head = layout.regions.firstWhere((r) => r.elementId == id);
        for (final c in curves) {
          expect(
            head.bounds.containsPoint(c.end),
            isFalse,
            reason: 'a curve ends on $id',
          );
        }
      }
    });

    test('laying the score out twice draws the same slurs', () {
      String render() =>
          _layout(score()).primitives.map((p) => p.toString()).join('\n');
      expect(render(), render());
    });
  });
}
