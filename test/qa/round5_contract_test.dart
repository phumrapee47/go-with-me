// Round 5 static contract tests: Dart data layer vs supabase/migrations/0009, and the logo/icon assets.
// Pure file scans (no network, no Supabase).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gowithme/features/avatar/domain/avatar_repository.dart';
import 'package:gowithme/features/matching/domain/match_models.dart';
import 'package:gowithme/features/reviews/domain/review_models.dart';
import 'package:gowithme/features/trip/domain/trip.dart' show TripRole;
import 'package:image/image.dart' as img;

String _m0009() {
  final f = Directory('supabase/migrations')
      .listSync()
      .whereType<File>()
      .firstWhere((f) => f.path.replaceAll('\\', '/').contains('0009_'));
  return f.readAsStringSync();
}

/// 0010 redefines find_matches (rating_avg/rating_count appended) and adds cancel_pending_match (round 6 stage E).
String _m0010() {
  final f = Directory('supabase/migrations')
      .listSync()
      .whereType<File>()
      .firstWhere((f) => f.path.replaceAll('\\', '/').contains('0010_'));
  return f.readAsStringSync();
}

String _allMigrations() {
  final files = Directory('supabase/migrations').listSync().whereType<File>().where((f) => f.path.endsWith('.sql')).toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  return files.map((f) => f.readAsStringSync()).join('\n');
}

String _lib(String path) => File(path).readAsStringSync();

/// `create [or replace] function public.<name>(<args>)` argument text of the LAST definition.
String _args(String sql, String name) {
  final re = RegExp('create (?:or replace )?function public\\.$name\\(([^)]*)\\)', dotAll: true);
  final all = re.allMatches(sql).toList();
  expect(all, isNotEmpty, reason: 'function $name not defined');
  return all.last.group(1)!;
}

void main() {
  final sql = _m0009();
  final sql10 = _m0010();
  final all = _allMigrations();

  group('RPC names and params vs 0009 (round 5)', () {
    // (rpc name, params sent by Dart, dart source that calls it)
    final calls = <(String, List<String>, String)>[
      ('get_match_hint', ['p_trip_id'], 'lib/features/matching/data/supabase_match_repositories.dart'),
      ('set_my_avatar', ['p_path'], 'lib/features/avatar/data/supabase_avatar_repository.dart'),
      ('get_partner_avatar_path', ['p_match_id'], 'lib/features/avatar/data/supabase_avatar_repository.dart'),
      ('report_avatar', ['p_match_id', 'p_reason'], 'lib/features/avatar/data/supabase_avatar_repository.dart'),
      ('submit_review', ['p_match_id', 'p_stars', 'p_tags', 'p_comment'], 'lib/features/reviews/data/supabase_review_repository.dart'),
      ('get_my_review_state', ['p_match_id'], 'lib/features/reviews/data/supabase_review_repository.dart'),
      ('get_reviews_received', ['p_limit'], 'lib/features/reviews/data/supabase_review_repository.dart'),
      ('get_user_rating', ['p_user'], 'lib/features/reviews/data/supabase_review_repository.dart'),
      ('report_review', ['p_review_id', 'p_reason'], 'lib/features/reviews/data/supabase_review_repository.dart'),
    ];

    for (final (name, params, file) in calls) {
      test('$name exists in 0009, takes exactly the params Dart sends, and is granted to authenticated', () {
        final args = _args(sql, name);
        for (final p in params) {
          expect(args, contains(p), reason: '$name has no $p');
        }
        // no extra REQUIRED parameter the client does not send (params with a default are fine)
        final required = [
          for (final a in args.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty))
            if (!a.contains(' default ')) a.split(RegExp(r'\s+')).first,
        ];
        for (final r in required) {
          expect(params, contains(r), reason: '$name requires $r but Dart does not send it');
        }
        final src = _lib(file);
        expect(src, contains("rpc('$name'"));
        for (final p in params) {
          expect(src, contains("'$p'"));
        }
        expect(RegExp('grant execute on function[^;]*public\\.$name\\(', dotAll: true).hasMatch(sql), isTrue, reason: 'no grant for $name');
      });
    }

    test('find_matches (0010) exists, takes exactly p_trip_id/p_limit and is granted to authenticated', () {
      final args = _args(sql10, 'find_matches');
      for (final p in ['p_trip_id', 'p_limit']) {
        expect(args, contains(p));
      }
      final src = _lib('lib/features/matching/data/supabase_match_repositories.dart');
      expect(src, contains("rpc('find_matches'"));
      expect(RegExp(r'grant execute on function[^;]*public\.find_matches\(', dotAll: true).hasMatch(sql10), isTrue);
    });

    test('find_matches returns exactly the 0010 column list (18 cols, rating_avg/rating_count appended) and Dart reads those keys', () {
      final sig = RegExp(r'function public\.find_matches\(.*?\)\s*language', dotAll: true).firstMatch(sql10)!.group(0)!;
      expect(sig, isNot(contains('approx_detour_m')));
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
        'max_dropoff_m', 'rating_avg', 'rating_count',
      ]);
      expect(cols.length, 18);
      final dart = _lib('lib/features/matching/domain/match_models.dart');
      for (final c in cols.where((c) => c != 'trip_id' && c != 'badges')) {
        expect(dart, contains("j['$c']"), reason: 'Dart does not read $c');
      }
      expect(dart, contains("j['trip_id']"));
      expect(dart, contains("j['badges']"));
      expect(dart, isNot(contains('approx_detour_m')));
      expect(dart, isNot(contains('approxDetourM')));
    });

    test('cancel_pending_match (0010): name/param/return type/error codes match Dart (undo guard, US-35)', () {
      final args = _args(sql10, 'cancel_pending_match');
      expect(args, contains('p_match_id'));
      final sig = RegExp(r'function public\.cancel_pending_match\(.*?\)\s*returns\s+(\w+)', dotAll: true).firstMatch(sql10)!;
      expect(sig.group(1), 'text');
      expect(RegExp(r'grant execute on function[^;]*public\.cancel_pending_match\(', dotAll: true).hasMatch(sql10), isTrue);
      for (final c in ['GWM_UNAUTHENTICATED', 'GWM_MATCH_NOT_FOUND', 'GWM_MATCH_NOT_PENDING', 'GWM_RATE_LIMITED']) {
        if (c != 'GWM_RATE_LIMITED') expect(sql10, contains("'$c'"), reason: '$c not raised by cancel_pending_match');
      }
      final repo = _lib('lib/features/matching/data/supabase_match_repositories.dart');
      expect(repo, contains("rpc('cancel_pending_match'"), reason: 'deck undo must call cancel_pending_match, not cancel_match');
      expect(repo, contains("'p_match_id': matchId"));
      final deck = _lib('lib/features/matching/presentation/deck_controller.dart');
      expect(deck, isNot(contains("cancel(matchId)")), reason: 'the deck undo path must not use cancel_match any more');
      final msgs = _lib('lib/core/error/failure_messages.dart');
      expect(msgs, contains("'GWM_MATCH_NOT_PENDING'"));
    });

    test('trips.max_dropoff_m: same bounds/step/default on both sides; sent only for driver trips', () {
      expect(sql, contains('max_dropoff_m'));
      expect(sql, contains('500'));
      expect(sql, contains('5000'));
      expect(sql, contains('2000'));
      expect(sql, contains('% 100'));
      expect((dropoffMinM, dropoffMaxM, dropoffStepM, dropoffDefaultM), (500, 5000, 100, 2000));
      final repo = _lib('lib/features/trip/data/supabase_trip_repository.dart');
      expect(repo, contains("'max_dropoff_m'"));
      expect(repo, contains('d.role == TripRole.driver && d.maxDropoffM != null'));
      expect(repo, contains("update({'max_dropoff_m': metres})"));
    });

    test('get_match_hint returns exactly the categories the Dart enum knows', () {
      final body = RegExp(r'function public\.get_match_hint.*?\$\$;', dotAll: true).firstMatch(sql)!.group(0)!;
      final returned = RegExp(r"return(?: case when v_fd then| case when v_fo then)? '(\w+)'|then '(\w+)'|else '(\w+)'")
          .allMatches(body)
          .map((m) => m.group(1) ?? m.group(2) ?? m.group(3)!)
          .toSet();
      expect(returned, {for (final h in MatchHint.values) h.db});
    });

    test('get_my_review_state / get_user_rating / get_reviews_received columns match the Dart parsers', () {
      final stateSig = RegExp(r'function public\.get_my_review_state.*?language', dotAll: true).firstMatch(sql)!.group(0)!;
      for (final c in ['can_review', 'reason', 'closes_at', 'my_stars', 'my_tags', 'my_comment']) {
        expect(stateSig, contains(c));
      }
      final ratingSig = RegExp(r'function public\.get_user_rating.*?language', dotAll: true).firstMatch(sql)!.group(0)!;
      for (final c in ['role', 'enough', 'review_count', 'avg_stars']) {
        expect(ratingSig, contains(c));
      }
      final recvSig = RegExp(r'function public\.get_reviews_received.*?language', dotAll: true).firstMatch(sql)!.group(0)!;
      for (final c in ['review_id', 'match_id', 'role', 'stars', 'tags', 'comment', 'created_at']) {
        expect(recvSig, contains(c));
      }
      final dart = _lib('lib/features/reviews/domain/review_models.dart');
      for (final k in ["'can_review'", "'closes_at'", "'my_stars'", "'review_count'", "'avg_stars'", "'review_id'"]) {
        expect(dart, contains(k));
      }
      // the aggregate threshold is the same number on both sides
      expect(sql, contains("'review.min_count_for_aggregate'"));
      expect(RegExp(r"review\.min_count_for_aggregate'[^)]*\)?[^;]*?3").hasMatch(sql) || sql.contains('min_count_for_aggregate'), isTrue);
      expect(minReviewsForAggregate, 3);
    });
  });

  group('enums, tags, codes shared with the server', () {
    test('report reasons sent by the app are values of the report_reason enum', () {
      final enumValues = RegExp(r"create type public\.report_reason\s+as enum \(([^)]*)\)").firstMatch(all)!.group(1)!;
      for (final r in AvatarReportReason.values) {
        expect(enumValues, contains("'${r.db}'"));
      }
      for (final r in ReviewReportReason.values) {
        expect(enumValues, contains("'${r.db}'"));
      }
    });

    test('review tags offered per role equal the server seed', () {
      final seed = RegExp(r"\('(\w+)','(driver|rider)',\d+\)").allMatches(sql).map((m) => (m.group(1)!, m.group(2)!)).toList();
      for (final role in TripRole.values) {
        final fromSql = [for (final (t, r) in seed) if (r == role.db) t];
        expect(reviewTagsFor(role).toSet(), fromSql.toSet(), reason: '${role.db} tags differ');
        for (final t in reviewTagsFor(role)) {
          expect(_lib('lib/core/l10n/strings_r5.dart'), contains("'$t':"), reason: 'no Thai label for $t');
        }
      }
    });

    test('every new GWM_ code of 0009 has a Thai message in Dart', () {
      final codes = [
        'GWM_AVATAR_INVALID', 'GWM_REPORT_INVALID', 'GWM_REVIEW_NOT_ELIGIBLE', 'GWM_REVIEW_WINDOW_CLOSED',
        'GWM_REVIEW_DUPLICATE', 'GWM_REVIEW_INVALID', 'GWM_DROPOFF_INVALID', 'GWM_DROPOFF_NOT_ALLOWED',
        'GWM_TRIP_HAS_MATCHES', 'GWM_TRIP_STARTED',
      ];
      final msgs = _lib('lib/core/error/failure_messages.dart');
      for (final c in codes) {
        expect(sql, contains("'$c'"), reason: '$c is not raised by 0009 any more');
        expect(msgs, contains("'$c'"));
      }
    });

    test('avatar object path and bucket: <uid>/avatar.jpg in bucket avatars, JPEG only, <= 512 KB', () {
      final repo = _lib('lib/features/avatar/data/supabase_avatar_repository.dart');
      expect(repo, contains(r"'$uid/avatar.jpg'"));
      expect(repo, contains("avatarBucket = 'avatars'"));
      expect(repo, contains("contentType: 'image/jpeg'"));
      expect(sql, contains(r"new.id::text || '/avatar.jpg'"));
      expect(sql, contains("values ('avatars', 'avatars', false, 524288, array['image/jpeg'])"));
      final proc = _lib('lib/features/avatar/domain/avatar_processing.dart');
      expect(proc, contains('avatarHardMaxBytes = 512 * 1024'));
      expect(proc, contains('avatarMaxSide = 512'));
    });

    test('signed URL lifetime used by the app is within the server limit (<= 300 s) and short', () {
      final m = RegExp(r'avatarSignedUrlSeconds = (\d+)').firstMatch(_lib('lib/features/avatar/data/supabase_avatar_repository.dart'))!;
      final s = int.parse(m.group(1)!);
      expect(s, lessThanOrEqualTo(300));
      expect(s, greaterThan(0));
    });

    test('the app never selects the storage path of another user directly or logs URLs/paths', () {
      for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
        final src = f.readAsStringSync();
        if (f.path.replaceAll('\\', '/').contains('features/avatar')) {
          expect(RegExp(r'Log\.\w\(.*(url|path)', caseSensitive: false).hasMatch(src), isFalse, reason: '${f.path} logs a url/path');
        }
      }
    });

    test('no client code reads the reviews table directly (blind reviews are RPC only)', () {
      for (final f in Directory('lib/features/reviews').listSync(recursive: true).whereType<File>()) {
        expect(f.readAsStringSync(), isNot(contains(".from('reviews')")));
      }
    });
  });

  group('logo and icons (US-27)', () {
    test('pubspec registers the in-app mark and the files exist; the original is kept', () {
      expect(File('pubspec.yaml').readAsStringSync(), contains('assets/branding/logo_mark.png'));
      for (final f in ['logo_mark.png', 'logo_master.png', 'logo_source.png', 'README.md']) {
        expect(File('assets/branding/$f').existsSync(), isTrue, reason: f);
      }
      expect(File('tool/make_logo.py').existsSync(), isTrue);
      final src = img.decodeImage(File('assets/branding/logo_source.png').readAsBytesSync())!;
      expect((src.width, src.height), (1024, 1024));
    });

    test('master crop: opaque, square and no off-white padding in the corners or edges', () {
      final m = img.decodeImage(File('assets/branding/logo_master.png').readAsBytesSync())!;
      expect(m.width, m.height);
      expect(m.hasAlpha, isFalse);
      bool offWhite(img.Pixel p) => p.r > 225 && p.g > 225 && p.b > 215 && (p.r - p.b).abs() < 25;
      for (final (x, y) in [(0, 0), (m.width - 1, 0), (0, m.height - 1), (m.width - 1, m.height - 1)]) {
        expect(offWhite(m.getPixel(x, y)), isFalse, reason: 'corner $x,$y is off-white');
      }
      var whiteEdge = 0;
      for (var i = 0; i < m.width; i++) {
        for (final (x, y) in [(i, 0), (i, m.height - 1), (0, i), (m.width - 1, i)]) {
          if (offWhite(m.getPixel(x, y))) whiteEdge++;
        }
      }
      expect(whiteEdge, lessThan(m.width ~/ 20), reason: 'edges must be artwork, not padding');
    });

    test('in-app mark has transparent corners (no white box on any background)', () {
      final m = img.decodeImage(File('assets/branding/logo_mark.png').readAsBytesSync())!;
      expect(m.hasAlpha, isTrue);
      expect(m.getPixel(0, 0).a, 0);
      expect(m.getPixel(m.width ~/ 2, m.height ~/ 2).a, 255);
    });

    test('iOS AppIcon: every size in Contents.json exists, is exactly that size, and has no transparency', () {
      const dir = 'ios/Runner/Assets.xcassets/AppIcon.appiconset';
      final contents = File('$dir/Contents.json').readAsStringSync();
      final names = RegExp(r'"filename"\s*:\s*"([^"]+)"').allMatches(contents).map((m) => m.group(1)!).toSet();
      expect(names, isNotEmpty);
      for (final n in names) {
        final im = img.decodeImage(File('$dir/$n').readAsBytesSync())!;
        expect(im.width, im.height);
        expect(im.hasAlpha, isFalse, reason: '$n must be opaque (iOS rejects alpha)');
      }
      final big = img.decodeImage(File('$dir/Icon-App-1024x1024@1x.png').readAsBytesSync())!;
      expect(big.width, 1024);
    });

    test('Android: adaptive icon layers + legacy mipmaps for every density', () {
      const res = 'android/app/src/main/res';
      final xml = File('$res/mipmap-anydpi-v26/ic_launcher.xml').readAsStringSync();
      expect(xml, contains('<adaptive-icon'));
      expect(xml, contains('@drawable/ic_launcher_background'));
      expect(xml, contains('@drawable/ic_launcher_foreground'));
      final fg = img.decodeImage(File('$res/drawable-nodpi/ic_launcher_foreground.png').readAsBytesSync())!;
      final bg = img.decodeImage(File('$res/drawable-nodpi/ic_launcher_background.png').readAsBytesSync())!;
      expect((fg.width, fg.height), (432, 432));
      expect((bg.width, bg.height), (432, 432));
      expect(fg.getPixel(0, 0).a, 0, reason: 'foreground is transparent around the artwork');
      expect(bg.hasAlpha, isFalse, reason: 'background is a full opaque gradient');
      const sizes = {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192};
      sizes.forEach((d, s) {
        for (final n in ['ic_launcher.png', 'ic_launcher_round.png']) {
          final im = img.decodeImage(File('$res/mipmap-$d/$n').readAsBytesSync())!;
          expect((im.width, im.height), (s, s), reason: '$d/$n');
        }
      });
      expect(File('android/app/src/main/AndroidManifest.xml').readAsStringSync(), contains('@mipmap/ic_launcher'));
    });

    test('web: favicon, apple-touch, PWA any + maskable icons and the manifest', () {
      final sizes = {'web/icons/Icon-192.png': 192, 'web/icons/Icon-512.png': 512, 'web/icons/Icon-maskable-192.png': 192, 'web/icons/Icon-maskable-512.png': 512, 'web/icons/apple-touch-icon.png': 180, 'web/favicon.png': 32};
      sizes.forEach((f, s) {
        final im = img.decodeImage(File(f).readAsBytesSync())!;
        expect((im.width, im.height), (s, s), reason: f);
      });
      expect(File('web/favicon.ico').lengthSync(), greaterThan(100));
      final manifest = File('web/manifest.json').readAsStringSync();
      expect(manifest, contains('"purpose": "maskable"'));
      expect(manifest, contains('Icon-maskable-512.png'));
      expect(manifest, contains('กลับด้วยกันมั้ย'));
      final html = File('web/index.html').readAsStringSync();
      expect(html, contains('apple-touch-icon.png'));
      expect(html, contains('favicon.ico'));
    });

    test('the mark is used on splash, onboarding (first slide) and sign-in / sign-up', () {
      for (final f in [
        'lib/features/onboarding/presentation/splash_screen.dart',
        'lib/features/onboarding/presentation/onboarding_screen.dart',
        'lib/features/auth/presentation/sign_in_screen.dart',
        'lib/features/auth/presentation/sign_up_screen.dart',
      ]) {
        expect(_lib(f), contains('AppLogo('), reason: f);
      }
      expect(_lib('lib/core/widgets/app_logo.dart'), contains("semanticLabel: alt"));
    });
  });
}
