import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 0008 narrows SELECT on `profiles` to a column list (the registration state must not leak to matched
/// partners). Any `select('*')` / bare `select()` on `profiles` would break at runtime, so guard the source.
const _granted = {
  'id',
  'display_name',
  'avatar_path',
  'locale',
  'adult_confirmed_at',
  'created_at',
  'updated_at',
  'deleted_at',
};

void main() {
  test('no Dart code reads profiles with select(*) and every column is in the 0008 grant', () {
    final files = Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'));
    final call = RegExp(r"from\('profiles'\)((?:.|\n)*?)\.select\(([^)]*)\)");
    var seen = 0;
    for (final f in files) {
      final src = f.readAsStringSync();
      for (final m in call.allMatches(src)) {
        seen++;
        var arg = m.group(2)!.trim();
        if (RegExp(r'^[A-Za-z_]\w*$').hasMatch(arg)) {
          // A named constant (e.g. _cols): resolve it in the same file.
          final def = RegExp("$arg\\s*=\\s*'([^']*)'").firstMatch(src);
          expect(def, isNotNull, reason: '${f.path}: cannot resolve $arg');
          arg = "'${def!.group(1)}'";
        }
        expect(arg, isNotEmpty, reason: '${f.path}: bare select() returns every column');
        final cols = arg.replaceAll("'", '').split(',').map((c) => c.trim()).where((c) => c.isNotEmpty);
        expect(cols, isNotEmpty, reason: f.path);
        for (final c in cols) {
          expect(c, isNot('*'), reason: '${f.path}: select(*) on profiles');
          expect(_granted, contains(c), reason: '${f.path}: $c is not readable on profiles after 0008');
        }
      }
    }
    expect(seen, greaterThanOrEqualTo(3), reason: 'the scan must actually find the existing profiles queries');
  });

  test('embedded profiles(...) selects (if any) never use *', () {
    final files = Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'));
    for (final f in files) {
      expect(f.readAsStringSync().contains('profiles(*)'), isFalse, reason: f.path);
    }
  });

  test('the new role columns are only reachable through get_my_role_state (no direct read in Dart)', () {
    final files = Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'));
    for (final f in files) {
      final src = f.readAsStringSync();
      for (final col in ['driver_registered', 'active_role', 'licence_declared_at', 'licence_declaration_version']) {
        final direct = RegExp("from\\('profiles'\\)[^;]*$col").hasMatch(src);
        expect(direct, isFalse, reason: '${f.path} reads $col directly');
      }
    }
  });
}
