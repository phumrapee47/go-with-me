import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:gowithme/features/auth/domain/auth_repository.dart';
import 'package:gowithme/features/matching/domain/match_models.dart';
import 'package:gowithme/features/trip/domain/trip.dart';

import 'fake_repos.dart';
import 'fakes.dart';

const testUser = AuthUser(id: 'u1', email: 'a@b.co', displayName: 'มิ้นท์', emailConfirmed: true);

/// Signed-in app on the home tab with a roomy viewport.
Future<Fakes> openApp(WidgetTester tester, Fakes f, {Size size = const Size(800, 2000)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(await buildTestApp(
    repo: FakeAuthRepository(initial: testUser),
    prefs: {'onboarding_done': true},
    fakes: f,
  ));
  await tester.pumpAndSettle();
  return f;
}

Future<void> goTo(WidgetTester tester, String path) async {
  final ctx = tester.element(find.byType(Scaffold).first);
  unawaited(GoRouter.of(ctx).push<void>(path));
  await tester.pumpAndSettle();
}

ProviderContainer containerOf(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));

/// A trip that is already in progress.
Trip runningTrip({String id = 'trip-1'}) =>
    sampleTrip(id: id).copyWith(status: TripStatus.inProgress, startedAt: DateTime.now());

MatchSummary acceptedMatch({String id = 'm1'}) =>
    sampleMatch(id: id, status: MatchStatus.accepted, iAmRequester: true);

Future<void> goBack(WidgetTester tester) async {
  final ctx = tester.element(find.byType(Scaffold).first);
  GoRouter.of(ctx).pop();
  await tester.pumpAndSettle();
}
