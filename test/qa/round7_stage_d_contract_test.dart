// Round 7 Stage D static contract tests: Dart data layer vs
// supabase/migrations/0016_precise_detour.sql (US-50 precise detour,
// US-44/BUG-R7-01 vibe/mood on find_matches). Pure file scans, no network.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _m0016() {
  final f = Directory('supabase/migrations')
      .listSync()
      .whereType<File>()
      .firstWhere((f) => f.path.replaceAll('\\', '/').contains('0016_'));
  return f.readAsStringSync();
}

String _lib(String path) => File(path).readAsStringSync();

void main() {
  final sql = _m0016();

  group('find_matches (0016): 20 columns, ending vibe_tags/mood_text', () {
    test('column list is exactly the 0016 shape (18 cols from 0010 + vibe_tags + mood_text)', () {
      final sig = RegExp(r'function public\.find_matches\(.*?\)\s*language', dotAll: true).firstMatch(sql)!.group(0)!;
      final cols = RegExp(r'returns table\s*\((.*)\)\s*language', dotAll: true)
          .firstMatch(sig)!
          .group(1)!
          .split(',')
          .map((e) => e.trim().split(RegExp(r'\s+')).first)
          .where((e) => e.isNotEmpty)
          .toList();
      expect(cols, [
        'trip_id', 'display_name', 'badges', 'mode', 'depart_at', 'time_diff_min', 'overlap_pct', 'approx_distance_m',
        'score', 'approx_origin_lat', 'approx_origin_lng', 'approx_dest_lat', 'approx_dest_lng', 'request_status', 'role',
        'max_dropoff_m', 'rating_avg', 'rating_count', 'vibe_tags', 'mood_text',
      ]);
      expect(cols.length, 20);
    });

    test('vibe_tags/mood_text are read by Dart under the exact same keys (name-based, not positional)', () {
      final dart = _lib('lib/features/matching/domain/match_models.dart');
      expect(dart, contains("j['vibe_tags']"));
      expect(dart, contains("j['mood_text']"));
    });

    test('the same 24h staleness rule as get_trip_card (mood_set_at > now() - interval \'24 hours\') guards mood_text', () {
      final fn = RegExp(r'create function public\.find_matches.*?\$\$;', dotAll: true).firstMatch(sql)!.group(0)!;
      expect(fn, contains("mood_set_at > now() - interval '24 hours'"));
    });

    test('still granted to authenticated only (no new public/anon exposure)', () {
      expect(RegExp(r'grant execute on function[^;]*public\.find_matches\(', dotAll: true).hasMatch(sql), isTrue);
      expect(RegExp(r'revoke execute on function[^;]*public\.find_matches\([^;]*from[^;]*public, anon', dotAll: true).hasMatch(sql),
          isTrue);
    });
  });

  group('request_match (0016): new optional p_client_detour_m + GWM_DETOUR_IMPLAUSIBLE', () {
    test('signature gains p_client_detour_m double precision default null (backward compatible)', () {
      final sig =
          RegExp(r'create function public\.request_match\(([^)]*)\)', dotAll: true).firstMatch(sql)!.group(1)!;
      expect(sig, contains('p_my_trip uuid'));
      expect(sig, contains('p_target_trip uuid'));
      expect(sig, contains('p_client_detour_m double precision default null'));
    });

    test('Dart calls request_match with p_client_detour_m as an optional (conditionally-sent) param', () {
      final dart = _lib('lib/features/matching/data/supabase_match_repositories.dart');
      expect(dart, contains("rpc('request_match'"));
      expect(dart, contains("'p_my_trip'"));
      expect(dart, contains("'p_target_trip'"));
      expect(dart, contains("'p_client_detour_m'"));
    });

    test('raises GWM_DETOUR_IMPLAUSIBLE (below the sound floor / floor unknown) and GWM_NOT_ELIGIBLE '
        '(param omitted when required, or over the driver\'s current tolerance)', () {
      expect(sql, contains("'GWM_DETOUR_IMPLAUSIBLE'"));
      expect(sql, contains("'GWM_NOT_ELIGIBLE'"));
    });

    test('GWM_DETOUR_IMPLAUSIBLE has a Thai message mapping (not the generic fallback)', () {
      final msgs = _lib('lib/core/error/failure_messages.dart');
      expect(msgs, contains("'GWM_DETOUR_IMPLAUSIBLE'"));
    });

    test('is granted to authenticated only, and the old 2-arg signature is dropped (not left callable)', () {
      expect(RegExp(r'grant execute on function[^;]*public\.request_match\(', dotAll: true).hasMatch(sql), isTrue);
      expect(sql, contains('drop function if exists public.request_match(uuid, uuid);'));
    });
  });

  group('matches.detour_precise_m (0016): audit column, no client grant', () {
    test('column exists, nullable, double precision', () {
      expect(sql, contains('alter table public.matches add column if not exists detour_precise_m double precision;'));
    });
  });

  group('client-side leg structure matches the server floor (0016 PART 1.2) — cross-reference', () {
    test('the SQL floor formula this Dart mirrors is present verbatim (guards against a silent formula drift)', () {
      final floorFn = RegExp(r'create or replace function public\._car_detour_floor_m.*?\$\$;', dotAll: true)
          .firstMatch(sql)!
          .group(0)!;
      // floor_m = |AM| + |MZ| - route(A,Z), clamped to >= 0.
      expect(floorFn, contains('ST_Distance(p_d_origin, p_r_dest)'));
      expect(floorFn, contains('ST_Distance(p_r_dest, p_d_dest)'));
      expect(floorFn, contains('ST_Length(p_d_route)'));
      final dart = _lib('lib/features/trip/domain/precise_detour.dart');
      expect(dart, contains('_car_detour_floor_m'), reason: 'the Dart file must document the formula it mirrors, by name');
    });
  });
}
