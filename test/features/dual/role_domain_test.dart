import 'package:flutter_test/flutter_test.dart';
import 'package:gowithme/core/error/app_failure.dart';
import 'package:gowithme/core/error/failure_messages.dart';
import 'package:gowithme/core/l10n/strings_dual.dart';
import 'package:gowithme/core/theme/tone.dart';
import 'package:gowithme/features/roles/domain/role_state.dart';
import 'package:gowithme/features/roles/presentation/role_providers.dart';
import 'package:gowithme/features/trip/domain/trip.dart';
import 'package:gowithme/features/vehicle/domain/vehicle.dart';

DriverRegistrationInput _in({String plate = '1กก 1234', String model = 'Yaris', String colour = 'ขาว', bool declared = true}) =>
    DriverRegistrationInput(plate: plate, model: model, colour: colour, declared: declared);

void main() {
  group('registration form validation', () {
    test('complete + declared is valid', () {
      expect(DriverRegistrationValidator.validate(_in()).isValid, isTrue);
    });

    test('the declaration is mandatory and never implied', () {
      final c = DriverRegistrationValidator.validate(_in(declared: false));
      expect(c.declarationMissing, isTrue);
      expect(c.fields, isEmpty);
      expect(c.isValid, isFalse);
    });

    test('uses the vehicle rules: empty and too long fields', () {
      final c = DriverRegistrationValidator.validate(_in(plate: '  ', model: 'x' * 61, colour: ''));
      expect(c.fields[VehicleField.plate], VehicleIssue.required);
      expect(c.fields[VehicleField.model], VehicleIssue.tooLong);
      expect(c.fields[VehicleField.color], VehicleIssue.required);
    });

    test('the app declaration version matches the server default (d1-draft)', () {
      expect(driverDeclarationVersion, 'd1-draft');
    });
  });

  group('default role of a car trip (roleTouched guard)', () {
    TripRole f({ActiveRole? a, bool reg = true, bool touched = false, TripRole? cur}) =>
        resolveTripRole(activeRole: a, registered: reg, roleTouched: touched, current: cur);

    test('follows the active role while untouched', () {
      expect(f(a: ActiveRole.driver), TripRole.driver);
      expect(f(a: ActiveRole.rider), TripRole.rider);
      expect(f(a: null), TripRole.rider, reason: 'unknown mode never guesses Driver');
    });

    test('an unregistered account never gets Driver by default', () {
      expect(f(a: ActiveRole.driver, reg: false), TripRole.rider);
    });

    test('the user choice is never overwritten by the mode', () {
      expect(f(a: ActiveRole.driver, touched: true, cur: TripRole.rider), TripRole.rider);
      expect(f(a: ActiveRole.rider, touched: true, cur: TripRole.driver), TripRole.driver);
    });

    test('an explicit Driver choice falls back to Rider once the registration is gone', () {
      expect(f(a: ActiveRole.rider, reg: false, touched: true, cur: TripRole.driver), TripRole.rider);
    });
  });

  group('switch state machine', () {
    test('idle -> switching -> idle; a second request while switching is ignored', () {
      var s = RoleSwitchState.idle.start(ActiveRole.driver);
      expect(s.isSwitching, isTrue);
      expect(s.target, ActiveRole.driver);
      expect(identical(s.start(ActiveRole.rider), s), isTrue);
      s = s.succeed();
      expect(s.phase, RoleSwitchPhase.idle);
    });

    test('failure keeps the reason and can be dismissed, then a new attempt is possible', () {
      var s = RoleSwitchState.idle.start(ActiveRole.driver).fail(RoleSwitchFailure.offline);
      expect(s.phase, RoleSwitchPhase.failed);
      expect(s.failure, RoleSwitchFailure.offline);
      s = s.dismiss();
      expect(s.phase, RoleSwitchPhase.idle);
      expect(s.start(ActiveRole.driver).isSwitching, isTrue);
    });

    test('succeed/fail outside of switching are no-ops', () {
      expect(RoleSwitchState.idle.succeed().phase, RoleSwitchPhase.idle);
      expect(RoleSwitchState.idle.fail(RoleSwitchFailure.generic).phase, RoleSwitchPhase.idle);
    });
  });

  group('reconcile with the server (F-D8)', () {
    test('cached Driver but no longer registered -> Rider and the user is told', () {
      final r = reconcileRole(cached: ActiveRole.driver, server: DriverRegistration.rider);
      expect(r.role, ActiveRole.rider);
      expect(r.forcedToRider, isTrue);
    });

    test('server value wins silently otherwise (switch made on another device)', () {
      const server = DriverRegistration(registered: true, activeRole: ActiveRole.driver);
      final r = reconcileRole(cached: ActiveRole.rider, server: server);
      expect(r.role, ActiveRole.driver);
      expect(r.forcedToRider, isFalse);
    });

    test('nothing cached: no notice', () {
      expect(reconcileRole(cached: null, server: DriverRegistration.rider).forcedToRider, isFalse);
    });
  });

  group('get_my_role_state parsing', () {
    test('full payload', () {
      final s = DriverRegistration.fromJson({
        'driver_registered': true,
        'driver_registered_at': '2026-05-01T10:00:00Z',
        'licence_declared_at': '2026-05-01T10:00:00Z',
        'licence_declaration_version': 'd1-draft',
        'active_role': 'driver',
        'roles': ['rider', 'driver'],
        'has_vehicle': true,
        'current_declaration_version': 'd1-draft',
      })!;
      expect(s.registered, isTrue);
      expect(s.activeRole, ActiveRole.driver);
      expect(s.declaredAt, isNotNull);
      expect(s.hasVehicle, isTrue);
      expect(s.currentDeclarationVersion, 'd1-draft');
    });

    test('Driver mode without registration is read as Rider (defensive)', () {
      final s = DriverRegistration.fromJson({'driver_registered': false, 'active_role': 'driver'})!;
      expect(s.activeRole, ActiveRole.rider);
    });

    test('garbage -> null', () {
      expect(DriverRegistration.fromJson(null), isNull);
      expect(DriverRegistration.fromJson('x'), isNull);
    });

    test('ActiveRole maps to the trip role and the tone', () {
      expect(ActiveRole.driver.tripRole, TripRole.driver);
      expect(ActiveRole.rider.tone, AppTone.rider);
      expect(ActiveRole.fromDb('nope'), isNull);
    });
  });

  group('Thai messages for the new GWM codes', () {
    const codes = [
      'GWM_NOT_A_DRIVER',
      'GWM_DRIVER_ACTIVE_TRIP',
      'GWM_DRIVER_ACTIVE_MATCH',
      'GWM_DRIVER_REGISTERED',
      'GWM_DECLARATION_REQUIRED',
      'GWM_DECLARATION_VERSION_STALE',
      'GWM_INVALID_ROLE',
    ];
    final generic = failureMessage(const AppFailure('GWM_SOMETHING_UNKNOWN'));
    final thai = RegExp('[฀-๿]');

    test('each has its own Thai text (not the generic fallback) and no server text', () {
      for (final c in codes) {
        final m = failureMessage(AppFailure(c));
        expect(m, isNot(generic), reason: c);
        expect(thai.hasMatch(m), isTrue, reason: '$c must be Thai');
        expect(m.contains('GWM_'), isFalse);
      }
    });

    test('copy carries no commercial or "we verify" wording', () {
      final all = [
        D.notice1, D.notice2, D.notice3, D.decl, D.declNote, D.driverCardTitle, D.driverCardBody, D.driverCardNote,
        D.gateBody, D.regCta, ...codes.map((c) => failureMessage(AppFailure(c))),
      ].join(' ');
      for (final bad in ['ค่าโดยสาร', 'ค่าบริการ', 'ราคา', 'ตรวจสอบแล้ว', 'รับรองโดยแอป', 'ยืนยันใบขับขี่แล้ว']) {
        expect(all.contains(bad), isFalse, reason: bad);
      }
      expect(D.notice1, contains('ยังไม่ผ่านการตรวจสอบ'));
    });

    test('unregister failures map to the blocked reasons', () {
      expect(unregisterBlockOf(const AppFailure('GWM_DRIVER_ACTIVE_TRIP')), UnregisterBlock.activeTrip);
      expect(unregisterBlockOf(const AppFailure('GWM_DRIVER_ACTIVE_MATCH')), UnregisterBlock.activeMatch);
      expect(unregisterBlockOf(const AppFailure('GWM_RATE_LIMITED')), isNull);
    });
  });
}
