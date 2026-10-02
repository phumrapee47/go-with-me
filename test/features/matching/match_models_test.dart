import 'package:flutter_test/flutter_test.dart';
import 'package:gowithme/features/matching/domain/match_models.dart';
import 'package:gowithme/features/trip/domain/travel_mode.dart';
import 'package:gowithme/features/trip/domain/trip.dart' show TripRole;

Map<String, dynamic> _row({Map<String, dynamic> overrides = const {}}) => {
      'trip_id': 'c1d2',
      'display_name': 'นุ่น',
      // Shape produced by user_badges(): a list of {kind,is_mock,org_name}.
      'badges': [
        {'kind': 'email', 'is_mock': false, 'org_name': null},
        {'kind': 'organization', 'is_mock': false, 'org_name': 'CU'},
      ],
      'mode': 'transit',
      'depart_at': '2026-09-25T13:00:00Z',
      'time_diff_min': 10,
      'overlap_pct': 72,
      'approx_distance_m': 1500,
      'score': 81.5,
      'approx_origin_lat': 13.7455,
      'approx_origin_lng': 100.5345,
      'approx_dest_lat': 13.9,
      'approx_dest_lng': 100.6,
      'request_status': null,
      ...overrides,
    };

void main() {
  test('maps a find_matches row', () {
    final c = MatchCandidate.fromJson(_row())!;
    expect(c.tripId, 'c1d2');
    expect(c.displayName, 'นุ่น');
    expect(c.mode, TravelMode.transit);
    expect(c.timeDiffMin, 10);
    expect(c.overlapPct, 72);
    expect(c.approxDistanceM, 1500);
    expect(c.score, 81.5);
    expect(c.approxOrigin.latitude, 13.7455);
    expect(c.approxDest!.longitude, 100.6);
    expect(c.requestStatus, isNull);
    expect(c.badges.map((b) => b.kind), ['email', 'organization']);
    expect(c.badges[1].label, contains('CU'));
    expect(c.departAt.toUtc(), DateTime.utc(2026, 9, 25, 13));
  });

  test('tolerates numeric strings/ints and clamps overlap to 0..100', () {
    final c = MatchCandidate.fromJson(_row(overrides: {
      'score': '80.00',
      'overlap_pct': 140,
      'approx_origin_lat': '13.7',
    }))!;
    expect(c.score, 80.0);
    expect(c.overlapPct, 100);
    expect(c.approxOrigin.latitude, 13.7);
  });

  test('request_status maps to enum, unknown ignored', () {
    expect(MatchCandidate.fromJson(_row(overrides: {'request_status': 'pending'}))!.requestStatus,
        MatchStatus.pending);
    expect(MatchCandidate.fromJson(_row(overrides: {'request_status': 'weird'}))!.requestStatus, isNull);
  });

  test('unusable rows are dropped instead of crashing the list', () {
    expect(MatchCandidate.fromJson(_row(overrides: {'mode': 'rocket'})), isNull);
    expect(MatchCandidate.fromJson(_row(overrides: {'approx_origin_lat': null})), isNull);
    expect(MatchCandidate.fromJson(_row(overrides: {'approx_dest_lat': null}))?.approxDest, isNull, reason: 'kept, dest is optional');
    expect(MatchCandidate.fromJson(_row(overrides: {'depart_at': 'nope'})), isNull);
    expect(MatchCandidate.fromJson(_row(overrides: {'trip_id': null})), isNull);
  });

  test('blank display name falls back and empty badges give an empty list', () {
    final c = MatchCandidate.fromJson(_row(overrides: {'display_name': '  ', 'badges': []}))!;
    expect(c.displayName, 'ผู้ใช้');
    expect(c.badges, isEmpty);
    expect(parseBadges(null), isEmpty);
  });

  test('mock phone badge is labelled as simulated', () {
    final b = parseBadges([
      {'kind': 'phone', 'is_mock': true},
    ]).single;
    expect(b.label, contains('จำลอง'));
  });

  test('withRequestStatus keeps everything else', () {
    final c = MatchCandidate.fromJson(_row())!;
    final d = c.withRequestStatus(MatchStatus.pending);
    expect(d.requestStatus, MatchStatus.pending);
    expect(d.tripId, c.tripId);
    expect(d.score, c.score);
  });

  group('rating_avg/rating_count (0010, 18 cols)', () {
    test('both present: parsed and hasRating is true', () {
      final c = MatchCandidate.fromJson(_row(overrides: {'rating_avg': 4.6, 'rating_count': 5}))!;
      expect(c.ratingAvg, 4.6);
      expect(c.ratingCount, 5);
      expect(c.hasRating, isTrue);
    });

    test('absent columns (older server): both null, no crash', () {
      final j = _row()..remove('rating_avg')..remove('rating_count');
      final j2 = Map<String, dynamic>.of(j);
      final c = MatchCandidate.fromJson(j2)!;
      expect(c.ratingAvg, isNull);
      expect(c.ratingCount, isNull);
      expect(c.hasRating, isFalse);
    });

    test('null values (server withheld, < 3 reviews): both null', () {
      final c = MatchCandidate.fromJson(_row(overrides: {'rating_avg': null, 'rating_count': null}))!;
      expect(c.ratingAvg, isNull);
      expect(c.ratingCount, isNull);
    });

    test('only one side present (should not happen server-side, but tolerate): both dropped to null', () {
      final c = MatchCandidate.fromJson(_row(overrides: {'rating_avg': 4.6, 'rating_count': null}))!;
      expect(c.ratingAvg, isNull);
      expect(c.ratingCount, isNull);
    });

    test('numeric string tolerated (postgres numeric over the wire)', () {
      final c = MatchCandidate.fromJson(_row(overrides: {'rating_avg': '4.60', 'rating_count': '5'}))!;
      expect(c.ratingAvg, 4.6);
      expect(c.ratingCount, 5);
    });
  });

  group('vibe_tags/mood_text (0016 Stage D, BUG-R7-01, 20 cols)', () {
    // The full 20-column shape find_matches (0016) now returns, ending in
    // vibe_tags/mood_text (docs/design-roles.md §16, migration 0016 PART 2).
    Map<String, dynamic> fullRow({Map<String, dynamic> overrides = const {}}) => _row(overrides: {
          'role': 'driver',
          'max_dropoff_m': 2000,
          'rating_avg': 4.6,
          'rating_count': 5,
          'vibe_tags': ['เงียบ', 'คุยได้'],
          'mood_text': 'วันนี้อารมณ์ดี',
          'mode': 'car',
          ...overrides,
        });

    test('end-to-end from a 20-column find_matches row: vibe/mood parsed and non-empty', () {
      final c = MatchCandidate.fromJson(fullRow())!;
      expect(c.vibeTags, ['เงียบ', 'คุยได้']);
      expect(c.moodText, 'วันนี้อารมณ์ดี');
      // The rest of the row still parses correctly alongside the two new columns.
      expect(c.role, TripRole.driver);
      expect(c.maxDropoffM, 2000);
      expect(c.hasRating, isTrue);
    });

    test('older server (columns absent): defaults, no crash', () {
      final j = fullRow()..remove('vibe_tags')..remove('mood_text');
      final c = MatchCandidate.fromJson(Map<String, dynamic>.of(j))!;
      expect(c.vibeTags, isEmpty);
      expect(c.moodText, isNull);
    });

    test('blank/whitespace-only mood_text normalises to null; non-string tags are dropped', () {
      final c = MatchCandidate.fromJson(fullRow(overrides: {
        'mood_text': '   ',
        'vibe_tags': ['เงียบ', 42, null],
      }))!;
      expect(c.moodText, isNull);
      expect(c.vibeTags, ['เงียบ']);
    });

    test('withRequestStatus / withoutRequest keep vibe/mood', () {
      final c = MatchCandidate.fromJson(fullRow())!;
      expect(c.withRequestStatus(MatchStatus.pending).vibeTags, c.vibeTags);
      expect(c.withoutRequest().moodText, c.moodText);
    });
  });
}
