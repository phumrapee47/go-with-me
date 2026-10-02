import 'package:flutter_test/flutter_test.dart';
import 'package:gowithme/features/trip/domain/trip.dart';
import 'package:gowithme/features/trip/domain/vibe_mood.dart';

void main() {
  group('VibeTagCatalog', () {
    test('driver and rider allow-lists match requirements US-44 AC1', () {
      expect(VibeTagCatalog.driverTags, [
        '#เปิดแอร์เย็น',
        '#เปิดเพลงฟังเพลิน',
        '#ขับนิ่มไม่ซิ่ง',
        '#ไม่สูบบุหรี่',
        '#มีที่เก็บกระเป๋า',
      ]);
      expect(VibeTagCatalog.riderTags, [
        '#คุยเก่ง',
        '#ขอพักสายตาเงียบๆ',
        '#ฟังเพลงสากล',
        '#สายประหยัด',
        '#พร้อมแชร์เรื่องเล่า',
      ]);
    });

    test('forRole: driver sees driver tags, everyone else sees rider tags', () {
      expect(VibeTagCatalog.forRole(TripRole.driver), VibeTagCatalog.driverTags);
      expect(VibeTagCatalog.forRole(TripRole.rider), VibeTagCatalog.riderTags);
      expect(VibeTagCatalog.forRole(null), VibeTagCatalog.riderTags);
    });
  });

  group('validateVibeTagSelection', () {
    test('rejects a tag outside the allow-list', () {
      expect(
        validateVibeTagSelection(current: const [], candidate: '#ไม่มีในลิสต์', role: null),
        VibeTagIssue.notInAllowList,
      );
    });

    test('allows up to 3 tags, rejects the 4th new one', () {
      final three = VibeTagCatalog.riderTags.take(3).toList();
      expect(
        validateVibeTagSelection(current: three, candidate: VibeTagCatalog.riderTags[3], role: null),
        VibeTagIssue.maxReached,
      );
    });

    test('re-selecting an already-selected tag at the cap is allowed (toggle off)', () {
      final three = VibeTagCatalog.riderTags.take(3).toList();
      expect(validateVibeTagSelection(current: three, candidate: three.first, role: null), isNull);
    });

    test('driver picking a rider tag is rejected (role-specific allow-list)', () {
      expect(
        validateVibeTagSelection(current: const [], candidate: VibeTagCatalog.riderTags.first, role: TripRole.driver),
        VibeTagIssue.notInAllowList,
      );
    });
  });

  group('VibeMoodValidator.validateMood (Q6 guard)', () {
    test('empty/blank is valid (optional field)', () {
      expect(VibeMoodValidator.validateMood(''), isNull);
      expect(VibeMoodValidator.validateMood('   '), isNull);
    });

    test('valid short text passes', () {
      expect(VibeMoodValidator.validateMood('วันนี้ขอฟังเพลงเงียบ ๆ นะ'), isNull);
    });

    test('over 35 chars is rejected', () {
      expect(VibeMoodValidator.validateMood('ก' * 36), MoodIssue.overLimit);
    });

    test('exactly 35 chars passes', () {
      expect(VibeMoodValidator.validateMood('ก' * 35), isNull);
    });

    test('8+ consecutive digits (phone-shaped) is rejected', () {
      expect(VibeMoodValidator.validateMood('โทร 081234567 นะ'), MoodIssue.blockedPattern);
    });

    test('7 consecutive digits is allowed (below the threshold)', () {
      expect(VibeMoodValidator.validateMood('เลข 1234567'), isNull);
    });

    test('blocklist word is rejected case-insensitively', () {
      for (final w in MoodBlocklist.words) {
        expect(VibeMoodValidator.validateMood('ทดสอบ $w คำ'), MoodIssue.blockedPattern);
      }
    });
  });

  group('vibeMoodExpired', () {
    test('null setAt is never expired', () {
      expect(vibeMoodExpired(null), isFalse);
    });

    test('expires at/after 24h', () {
      final now = DateTime(2026, 1, 2, 12);
      expect(vibeMoodExpired(now.subtract(const Duration(hours: 24)), now: now), isTrue);
      expect(vibeMoodExpired(now.subtract(const Duration(hours: 23, minutes: 59)), now: now), isFalse);
    });
  });

  group('Trip/TripDraft round 7 fields', () {
    test('Trip.fromJson parses vibe_tags/mood_text/mood_set_at/women_only tolerantly', () {
      final t = Trip.fromJson({
        'id': 't1',
        'mode': 'car',
        'status': 'scheduled',
        'origin': {
          'type': 'Point',
          'coordinates': [100.5, 13.7],
        },
        'dest': {
          'type': 'Point',
          'coordinates': [100.6, 13.8],
        },
        'depart_at': '2026-01-01T00:00:00Z',
        'vibe_tags': ['#ไม่สูบบุหรี่'],
        'mood_text': 'สวัสดี',
        'mood_set_at': '2026-01-01T00:00:00Z',
        'women_only': true,
      });
      expect(t, isNotNull);
      expect(t!.vibeTags, ['#ไม่สูบบุหรี่']);
      expect(t.moodText, 'สวัสดี');
      expect(t.moodSetAt, isNotNull);
      expect(t.womenOnly, isTrue);
    });

    test('Trip.fromJson defaults round-7 fields when the server omits them (older row)', () {
      final t = Trip.fromJson({
        'id': 't2',
        'mode': 'walk',
        'status': 'scheduled',
        'origin': {
          'type': 'Point',
          'coordinates': [100.5, 13.7],
        },
        'dest': {
          'type': 'Point',
          'coordinates': [100.6, 13.8],
        },
        'depart_at': '2026-01-01T00:00:00Z',
      });
      expect(t, isNotNull);
      expect(t!.vibeTags, isEmpty);
      expect(t.moodText, isNull);
      expect(t.womenOnly, isFalse);
    });
  });
}
