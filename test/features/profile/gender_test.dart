import 'package:flutter_test/flutter_test.dart';
import 'package:gowithme/features/profile/domain/gender.dart';

void main() {
  group('Gender', () {
    test('fromDb round-trips every value', () {
      for (final g in Gender.values) {
        expect(Gender.fromDb(g.db), g);
      }
    });

    test('fromDb returns null for unknown/missing values (never guesses)', () {
      expect(Gender.fromDb(null), isNull);
      expect(Gender.fromDb('nonsense'), isNull);
    });

    test('only female unlocks Women-Only (US-45 AC)', () {
      expect(Gender.female.unlocksWomenOnly, isTrue);
      expect(Gender.male.unlocksWomenOnly, isFalse);
      expect(Gender.unspecified.unlocksWomenOnly, isFalse);
    });
  });
}
