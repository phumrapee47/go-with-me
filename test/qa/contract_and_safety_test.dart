// QA static contract tests: Dart data layer vs supabase/migrations, secrets,
// demo-mode default. Pure file scans, no network / no Supabase.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gowithme/core/config/app_constants.dart';
import 'package:gowithme/demo/demo_mode.dart';
import 'package:gowithme/features/auth/presentation/auth_validators.dart';

// Every migration counts: later ones (0006 roles) add RPCs and GWM_ codes the app uses.
String _migrations() {
  final files = Directory('supabase/migrations')
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.sql'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  return files.map((f) => f.readAsStringSync()).join('\n');
}

Iterable<File> _libFiles({bool includeDemo = true}) => Directory('lib')
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .where((f) => includeDemo || !f.path.replaceAll('\\', '/').contains('lib/demo/'));

void main() {
  group('RPC contract (Dart -> SQL)', () {
    final sql = _migrations();
    final rpcRe = RegExp(r"\.rpc\(\s*'(\w+)'(?:\s*,\s*params:\s*\{([^}]*)\})?", dotAll: true);

    test('every rpc name and param key used in lib exists in the migrations', () {
      final problems = <String>[];
      var seen = 0;
      for (final f in _libFiles(includeDemo: false)) {
        final src = f.readAsStringSync();
        for (final m in rpcRe.allMatches(src)) {
          seen++;
          final name = m.group(1)!;
          final defRe = RegExp('function public\\.$name\\(([^)]*)\\)', dotAll: true);
          final defs = defRe.allMatches(sql).toList();
          if (defs.isEmpty) {
            problems.add('${f.path}: rpc $name not defined');
            continue;
          }
          final params = RegExp(r"'(p_\w+)'\s*:").allMatches(m.group(2) ?? '').map((e) => e.group(1)!);
          for (final p in params) {
            if (!defs.any((d) => d.group(1)!.contains(p))) {
              problems.add('${f.path}: rpc $name has no param $p');
            }
          }
        }
      }
      expect(seen, greaterThan(10));
      expect(problems, isEmpty);
    });

    test('every GWM_ code raised by SQL has a Thai message mapping in Dart', () {
      final raised = RegExp(r"'(GWM_[A-Z_]+)'").allMatches(sql).map((m) => m.group(1)!).toSet();
      final dart = Directory('lib/core/error')
          .listSync()
          .whereType<File>()
          .map((f) => f.readAsStringSync())
          .join('\n');
      final missing = raised.where((c) => !dart.contains("'$c'")).toList();
      expect(missing, isEmpty);
    });

    test('tables written by the app are granted insert/update columns the app sends', () {
      // trips.insert sends `id` (client UUID) -> needs the 0002 column grant
      expect(sql, contains('grant insert (id) on public.trips'));
      expect(sql, contains('grant insert (id) on public.sos_events'));
    });
  });

  group('secrets / demo mode', () {
    test('DEMO_MODE is false unless --dart-define is passed', () {
      expect(demoModeEnabled, isFalse);
      final src = File('lib/demo/demo_mode.dart').readAsStringSync();
      expect(src, contains("bool.fromEnvironment('DEMO_MODE')")); // no defaultValue: true
      expect(src, isNot(contains('defaultValue: true')));
    });

    test('demo code is only referenced from main.dart and the router hook', () {
      final users = _libFiles(includeDemo: false)
          .where((f) => f.readAsStringSync().contains("demo/"))
          .map((f) => f.path.replaceAll('\\', '/'))
          .toList();
      expect(users.toSet().difference({'lib/main.dart', 'lib/core/router/app_router.dart'}), isEmpty);
    });

    test('no service_role / secret key / JWT / project URL committed in lib, env example or README', () {
      final jwt = RegExp(r'eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{10,}');
      final projectUrl = RegExp(r'https://(?!YOUR-PROJECT-REF)[a-z0-9]{15,}\.supabase\.co');
      for (final f in [..._libFiles(), File('env.example.json'), File('README.md')]) {
        final s = f.readAsStringSync();
        expect(jwt.hasMatch(s), isFalse, reason: '${f.path} contains a JWT');
        expect(projectUrl.hasMatch(s), isFalse, reason: '${f.path} contains a project URL');
        expect(s.contains('sb_secret_') && !f.path.endsWith('app_config.dart') && !f.path.endsWith('README.md'), isFalse,
            reason: '${f.path} mentions sb_secret_');
      }
    });

    test('.gitignore covers env files', () {
      final g = File('.gitignore').readAsStringSync();
      expect(g, contains('.env*'));
      expect(g, contains('env/*.json'));
    });

    test('no Supabase URL/key literals are passed to Supabase.initialize', () {
      final main = File('lib/main.dart').readAsStringSync();
      expect(main, contains('config.url'));
      expect(main, isNot(RegExp(r"url:\s*'https?://")));
    });
  });

  group('email / password validators (US-2 AC2)', () {
    test('email format', () {
      for (final ok in ['a@b.co', ' user@mail.uni.ac.th ', 'x+y@gmail.com']) {
        expect(validateEmail(ok), isNull, reason: ok);
      }
      for (final bad in ['', 'abc', 'a@b', 'a b@c.com', '@x.com', 'a@.com', null]) {
        expect(validateEmail(bad), isNotNull, reason: '$bad');
      }
    });

    test('password minimum 8', () {
      expect(validatePassword('1234567'), isNotNull);
      expect(validatePassword('12345678'), isNull);
      expect(validatePassword(null), isNotNull);
    });

    test('display name required', () {
      expect(validateDisplayName('  '), isNotNull);
      expect(validateDisplayName('มิ้นท์'), isNull);
    });
  });

  group('live-push interval vs requirement (US-12: 15 s default, 15-30 s configurable)', () {
    test('app pushes every 15 s (within 15-30 s)', () {
      final secs = AppConstants.livePushInterval().inSeconds;
      expect(secs >= 15 && secs <= 30, isTrue);
    });

    test('DB rate guard stays 5 s: 3x headroom under the 15 s client interval', () {
      final sql = _migrations();
      expect(sql, contains("recorded_at > now() - interval '5 seconds'"));
    });
  });
}
