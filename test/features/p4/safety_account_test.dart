import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gowithme/core/l10n/strings.dart';
import 'package:gowithme/core/l10n/strings_p4.dart';
import 'package:gowithme/core/router/redirect.dart';
import 'package:gowithme/features/safety/domain/safety_models.dart';
import 'package:gowithme/features/safety/presentation/safety_providers.dart';
import 'package:gowithme/features/trip/domain/trip.dart';

import '../../support/fake_repos.dart';
import '../../support/fakes.dart';
import '../../support/p4_helpers.dart';

Future<void> _fillContact(WidgetTester tester, String name, String phone) async {
  final fields = find.byType(TextFormField);
  await tester.enterText(fields.at(0), name);
  await tester.enterText(fields.at(1), phone);
  await tester.tap(find.text(P.contactSave));
  await tester.pumpAndSettle();
}

void main() {
  group('emergency contacts', () {
    testWidgets('empty state, add, list shows a masked number', (tester) async {
      final f = Fakes();
      await openApp(tester, f);
      await goTo(tester, Routes.safetyContacts);
      expect(find.text(P.contactsEmpty), findsOneWidget);

      await tester.tap(find.text(P.contactsAdd));
      await tester.pumpAndSettle();
      await _fillContact(tester, 'แม่', '081-234-5678');

      expect(f.contacts.items.single.phone, '0812345678', reason: 'normalised before saving');
      expect(find.text('แม่'), findsOneWidget);
      expect(find.text('xxxxxx5678'), findsOneWidget);
      expect(find.text('1/3 ราย'), findsOneWidget);
    });

    testWidgets('validation: bad phone and empty name are rejected inline', (tester) async {
      final f = Fakes();
      await openApp(tester, f);
      await goTo(tester, Routes.contactEdit());
      await _fillContact(tester, '', '123');
      expect(find.text(P.errContactName), findsOneWidget);
      expect(find.text(P.errContactPhone), findsOneWidget);
      expect(f.contacts.items, isEmpty);
    });

    testWidgets('limit: the add button is disabled at 3 with an explanation', (tester) async {
      final f = Fakes();
      for (var i = 0; i < 3; i++) {
        f.contacts.items.add(EmergencyContact(id: 'c$i', name: 'คน$i', phone: '08100000${i}0'));
      }
      await openApp(tester, f);
      await goTo(tester, Routes.safetyContacts);
      expect(find.text('3/3 ราย'), findsOneWidget);
      final add = tester.widget<FilledButton>(find.widgetWithText(FilledButton, P.contactsAdd));
      expect(add.onPressed, isNull);
      expect(find.text(P.contactsMax), findsOneWidget);
    });

    testWidgets('the app itself refuses a 4th contact even if the button were reached', (tester) async {
      final f = Fakes();
      for (var i = 0; i < 3; i++) {
        f.contacts.items.add(EmergencyContact(id: 'c$i', name: 'คน$i', phone: '08100000${i}0'));
      }
      await openApp(tester, f);
      await goTo(tester, Routes.contactEdit());
      await _fillContact(tester, 'คนที่สี่', '0899999999');
      expect(f.contacts.items, hasLength(3));
      expect(find.text('เพิ่มผู้ติดต่อฉุกเฉินได้ไม่เกิน 3 ราย'), findsOneWidget);
    });

    testWidgets('duplicate number is caught on the phone field', (tester) async {
      final f = Fakes();
      f.contacts.items.add(const EmergencyContact(id: 'c0', name: 'แม่', phone: '0812345678'));
      await openApp(tester, f);
      await goTo(tester, Routes.contactEdit());
      await _fillContact(tester, 'พ่อ', '081 234 5678');
      expect(find.text(P.errContactDuplicate), findsOneWidget);
      expect(f.contacts.items, hasLength(1));
    });

    testWidgets('edit keeps the id and updates fields', (tester) async {
      final f = Fakes();
      f.contacts.items.add(const EmergencyContact(id: 'c0', name: 'แม่', phone: '0812345678'));
      await openApp(tester, f);
      await goTo(tester, Routes.contactEdit(id: 'c0'));
      expect(find.widgetWithText(TextFormField, 'แม่'), findsOneWidget);
      await _fillContact(tester, 'แม่ใหญ่', '0812345678');
      expect(f.contacts.items.single.id, 'c0');
      expect(f.contacts.items.single.name, 'แม่ใหญ่');
    });

    testWidgets('deleting one of several: plain confirmation', (tester) async {
      final f = Fakes();
      f.contacts.items.addAll(const [
        EmergencyContact(id: 'c0', name: 'แม่', phone: '0812345678'),
        EmergencyContact(id: 'c1', name: 'พ่อ', phone: '0898765432'),
      ]);
      await openApp(tester, f);
      await goTo(tester, Routes.safetyContacts);
      await tester.tap(find.byTooltip('${P.contactDelete} แม่'));
      await tester.pumpAndSettle();
      expect(find.text(P.contactDeleteLastBody), findsNothing);
      await tester.tap(find.widgetWithText(FilledButton, P.contactDelete));
      await tester.pumpAndSettle();
      expect(f.contacts.items.single.id, 'c1');
    });

    testWidgets('deleting the LAST contact warns that SOS will notify nobody, and is still allowed',
        (tester) async {
      final f = Fakes();
      f.contacts.items.add(const EmergencyContact(id: 'c0', name: 'แม่', phone: '0812345678'));
      await openApp(tester, f);
      await goTo(tester, Routes.safetyContacts);
      await tester.tap(find.byTooltip('${P.contactDelete} แม่'));
      await tester.pumpAndSettle();
      expect(find.textContaining('SOS จะไม่ส่งข้อความหาใคร'), findsOneWidget);

      await tester.tap(find.text(P.contactDeleteKeep));
      await tester.pumpAndSettle();
      expect(f.contacts.items, hasLength(1));

      await tester.tap(find.byTooltip('${P.contactDelete} แม่'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, P.contactDelete));
      await tester.pumpAndSettle();
      expect(f.contacts.items, isEmpty);
    });

    testWidgets('contacts are cached locally so SOS can read them without a network', (tester) async {
      final f = Fakes();
      f.contacts.items.add(const EmergencyContact(id: 'c0', name: 'แม่', phone: '0812345678'));
      await openApp(tester, f);
      await goTo(tester, Routes.safetyContacts);
      final cached = containerOf(tester).read(contactCacheProvider).read();
      expect(cached.single.name, 'แม่');
    });

    testWidgets('home nudges to set contacts when there are none (not a blocker)', (tester) async {
      await openApp(tester, Fakes());
      expect(find.text(P.noContactsCard), findsOneWidget);
      await tester.tap(find.text(P.noContactsCard));
      await tester.pumpAndSettle();
      expect(find.text(P.contactsTitle), findsWidgets);
    });
  });

  group('safety hub and block list', () {
    testWidgets('hub: contacts, emergency numbers call, tips', (tester) async {
      final f = Fakes();
      f.contacts.items.add(const EmergencyContact(id: 'c0', name: 'แม่', phone: '0812345678'));
      await openApp(tester, f);
      await tester.tap(find.byTooltip(P.safetyShield));
      await tester.pumpAndSettle();
      expect(find.text(P.contactsTitle), findsOneWidget);
      await tester.tap(find.text(P.sosCall191));
      await tester.tap(find.text(P.sosCall1669));
      expect(f.actions.calls, ['191', '1669']);
      expect(find.text(P.tip1), findsOneWidget);
      expect(find.text(P.noShares), findsOneWidget, reason: 'no backend links without a share page');
    });

    testWidgets('blocked users: list and unblock with confirmation', (tester) async {
      final f = Fakes();
      f.safety.blockedIds.add('someone');
      await openApp(tester, f);
      await goTo(tester, Routes.blocked);
      expect(find.text('คนที่บล็อก'), findsOneWidget);
      await tester.tap(find.text(P.unblock));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, P.unblock));
      await tester.pumpAndSettle();
      expect(f.safety.blockedIds, isEmpty);
      expect(find.text(P.blockedEmpty), findsOneWidget);
    });
  });

  group('share trip', () {
    Fakes withTrip() => Fakes()
      ..trips.active = runningTrip()
      ..matches.matches = [acceptedMatch()];

    testWidgets('P0 snapshot: text through the share sheet, says it cannot be recalled, no stop button',
        (tester) async {
      final f = withTrip();
      await openApp(tester, f);
      await goTo(tester, Routes.tripShare('trip-1'));

      expect(find.text(P.shareSnapshotWarning), findsOneWidget);
      expect(find.text(P.shareWontShare), findsOneWidget);
      await tester.tap(find.text(P.shareSend));
      await tester.pumpAndSettle();

      final text = f.actions.shared.single;
      expect(text, contains('มิ้นท์'));
      expect(text, contains('รังสิต'));
      expect(text, isNot(contains('ติดตามต่อ')));
      expect(f.shares.created, 0, reason: 'no backend token without a share page');
      expect(find.text(P.shareSentSnapshot), findsOneWidget);
      expect(find.text(P.shareStop), findsNothing);
    });

    testWidgets('with a backend share page: link is minted, warning changes, stop revokes it', (tester) async {
      final f = withTrip()..shareBaseUrl = 'https://share.example';
      await openApp(tester, f);
      await goTo(tester, Routes.tripShare('trip-1'));
      expect(find.text(P.shareLinkWarning), findsOneWidget);

      await tester.tap(find.text(P.shareSend));
      await tester.pumpAndSettle();
      expect(f.shares.created, 1);
      expect(f.actions.shared.single, contains('https://share.example/t#tok1'));
      expect(find.text(P.shareActive), findsOneWidget);

      await tester.tap(find.text(P.shareStop));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, P.shareStop));
      await tester.pumpAndSettle();
      expect(f.shares.revoked, ['share-1']);
      expect(find.text(P.shareActive), findsNothing);
    });

    testWidgets('safety hub lists revocable links and can stop them', (tester) async {
      final f = withTrip()..shareBaseUrl = 'https://share.example';
      await f.shares.create('trip-1');
      await openApp(tester, f);
      await goTo(tester, Routes.safety);
      expect(find.text(P.shareActive), findsOneWidget);
      await tester.tap(find.text(P.shareStop));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, P.shareStop));
      await tester.pumpAndSettle();
      expect(f.shares.shares, isEmpty);
    });

    testWidgets('an unavailable share sheet is reported, not swallowed', (tester) async {
      final f = withTrip();
      f.actions.shareOk = false;
      await openApp(tester, f);
      await goTo(tester, Routes.tripShare('trip-1'));
      await tester.tap(find.text(P.shareSend));
      await tester.pumpAndSettle();
      expect(find.text(P.shareUnavailable), findsOneWidget);
      expect(find.text(P.shareSentSnapshot), findsNothing);
    });

    testWidgets('shareable from a scheduled trip detail too', (tester) async {
      final f = Fakes()..trips.active = sampleTrip();
      await openApp(tester, f);
      await goTo(tester, Routes.tripDetail('trip-1'));
      await tester.tap(find.text(P.shareTripButton));
      await tester.pumpAndSettle();
      expect(find.text(P.shareTitle), findsWidgets);
      expect(f.trips.active!.status, TripStatus.scheduled);
    });
  });

  group('privacy, consent and account', () {
    testWidgets('location switch: turning off explains, confirms and logs a withdrawn consent', (tester) async {
      final f = Fakes();
      await openApp(tester, f);
      await goTo(tester, Routes.settingsPrivacy);
      expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value, isTrue);

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(find.text(P.locationSwitchOffTitle), findsOneWidget);
      await tester.tap(find.text(P.locationSwitchOffKeep));
      await tester.pumpAndSettle();
      expect(f.consent.log, isEmpty, reason: 'declined: nothing recorded');

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      await tester.tap(find.text(P.locationSwitchOffConfirm));
      await tester.pumpAndSettle();
      expect(f.consent.log, [false]);
      expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value, isFalse);

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(f.consent.log, [false, true], reason: 'turning on needs no confirmation');
    });

    testWidgets('data export stub prepares the JSON and offers the share sheet', (tester) async {
      final f = Fakes();
      await openApp(tester, f);
      await goTo(tester, Routes.settingsPrivacy);
      final exportButton = find.widgetWithText(OutlinedButton, P.exportData);
      await tester.scrollUntilVisible(exportButton, 200);
      await tester.tap(exportButton);
      await tester.pumpAndSettle();
      expect(find.text(P.exportReady), findsOneWidget);
      await tester.tap(find.text(P.exportShare));
      await tester.pumpAndSettle();
      expect(f.actions.shared.single, contains('profile'));
      expect(f.account.exports, 1);
    });

    testWidgets('settings lists privacy, policy, terms and the delete-account entry', (tester) async {
      await openApp(tester, Fakes());
      await goTo(tester, Routes.settings);
      expect(find.text(P.settingsPrivacy), findsOneWidget);
      expect(find.text(S.policy), findsOneWidget);
      expect(find.text(S.terms), findsOneWidget);
      expect(find.text(P.deleteAccountRow), findsOneWidget);
    });

    testWidgets('delete account: needs the typed phrase and a final confirmation, then signs out', (tester) async {
      final f = Fakes();
      await openApp(tester, f);
      await goTo(tester, Routes.settingsDeleteAccount);
      final button = find.widgetWithText(FilledButton, P.deleteButton);
      expect(tester.widget<FilledButton>(button).onPressed, isNull);

      await tester.enterText(find.byType(TextField), 'ลบ');
      await tester.pump();
      expect(tester.widget<FilledButton>(button).onPressed, isNull, reason: 'partial phrase');

      await tester.enterText(find.byType(TextField), P.deletePhrase);
      await tester.pump();
      expect(tester.widget<FilledButton>(button).onPressed, isNotNull);

      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.text(P.deleteConfirmTitle), findsOneWidget);
      await tester.tap(find.text(P.deleteConfirmKeep));
      await tester.pumpAndSettle();
      expect(f.account.deletions, 0);

      await tester.tap(button);
      await tester.pumpAndSettle();
      await tester.tap(find.text(P.deleteConfirmYes));
      await tester.pumpAndSettle();
      expect(f.account.deletions, 1);
      expect(find.text(S.signIn), findsWidgets, reason: 'signed out immediately');
    });

    testWidgets('policy and terms are reachable from the Me tab', (tester) async {
      await openApp(tester, Fakes());
      await tester.tap(find.text(S.tabMe));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text(S.policy), 200);
      await tester.tap(find.text(S.policy));
      await tester.pumpAndSettle();
      expect(find.text(S.draftNotice), findsOneWidget);
    });
  });
}
