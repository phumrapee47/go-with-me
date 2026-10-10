import 'package:flutter_test/flutter_test.dart';
import 'package:gowithme/features/profile/domain/gender.dart';

void main() {
  group('Gender', () {
    test('fromDb round-trips every value', () {
      for (final g in Gender.values) {
        expect(Gender.fromDb(g.db), g);
      }
    });

    test('every value the client can send satisfies the DB check profiles_gender_chk (female|male|other)', () {
      // supabase/migrations/0012_vibe_filters.sql: gender in ('female','male','other'). A mismatch makes the update
      // fail on the server (it did for "ไม่ระบุ" while it was sent as 'unspecified').
      for (final g in Gender.values) {
        expect(const {'female', 'male', 'other'}, contains(g.db), reason: '${g.name} would be rejected by the DB');
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
