import 'package:flutter_test/flutter_test.dart';
import 'package:gowithme/core/error/app_failure.dart';
import 'package:gowithme/features/matching/data/request_flow.dart';
import 'package:gowithme/features/matching/domain/match_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

PostgrestException _gwm(String code) => PostgrestException(message: code, code: 'P0001');

Future<void> _noSleep(Duration _) async {}

void main() {
  test('happy path returns the id and the re-read status', () async {
    final o = await runRequestMatch(
      callRpc: () async => 'm1',
      lookup: () async => (id: 'm1', status: MatchStatus.accepted, iAmRequester: false),
      sleep: _noSleep,
    );
    expect(o.matchId, 'm1');
    expect(o.status, MatchStatus.accepted); // mutual request auto-accepted
    expect(o.iAmRequester, isFalse);
  });

  test('lookup failure after success still reports pending', () async {
    final o = await runRequestMatch(
      callRpc: () async => 'm1',
      lookup: () async => throw StateError('offline'),
      sleep: _noSleep,
    );
    expect(o.status, MatchStatus.pending);
  });

  test('timeout is retried with the same arguments and succeeds', () async {
    var calls = 0;
    final o = await runRequestMatch(
      callRpc: () async {
        calls++;
        if (calls == 1) throw const PostgrestException(message: 'x', code: '503');
        return 'm1';
      },
      lookup: () async => null,
      sleep: _noSleep,
    );
    expect(calls, 2);
    expect(o.matchId, 'm1');
  });

  test('ALREADY_REQUESTED after an earlier attempt resolves to that match (success)', () async {
    final o = await runRequestMatch(
      callRpc: () async => throw _gwm('GWM_ALREADY_REQUESTED'),
      lookup: () async => (id: 'm9', status: MatchStatus.pending, iAmRequester: true),
      sleep: _noSleep,
    );
    expect(o.matchId, 'm9');
    expect(o.status, MatchStatus.pending);
  });

  test('ALREADY_EXISTS where the other side requested first -> matched', () async {
    final o = await runRequestMatch(
      callRpc: () async => throw _gwm('GWM_ALREADY_EXISTS'),
      lookup: () async => (id: 'm5', status: MatchStatus.accepted, iAmRequester: false),
      sleep: _noSleep,
    );
    expect(o.status, MatchStatus.accepted);
    expect(o.iAmRequester, isFalse);
  });

  test('ALREADY_REQUESTED but the request was declined stays a failure', () async {
    await expectLater(
      runRequestMatch(
        callRpc: () async => throw _gwm('GWM_ALREADY_REQUESTED'),
        lookup: () async => (id: 'm9', status: MatchStatus.declined, iAmRequester: true),
        sleep: _noSleep,
      ),
      throwsA(isA<AppFailure>().having((f) => f.code, 'code', 'GWM_ALREADY_REQUESTED')),
    );
  });

  test('business errors are not retried', () async {
    var calls = 0;
    await expectLater(
      runRequestMatch(
        callRpc: () async {
          calls++;
          throw _gwm('GWM_PENDING_LIMIT');
        },
        lookup: () async => null,
        sleep: _noSleep,
      ),
      throwsA(isA<AppFailure>().having((f) => f.code, 'code', 'GWM_PENDING_LIMIT')),
    );
    expect(calls, 1);
  });

  group('resolveByRefetch', () {
    test('MATCH_NOT_FOUND on repeat is success when the refetch shows the target state', () async {
      final s = await resolveByRefetch<MatchStatus>(
        sleep: _noSleep,
        action: () async => throw _gwm('GWM_MATCH_NOT_FOUND'),
        staleCodes: {'GWM_MATCH_NOT_FOUND'},
        refetchIfDone: () async => MatchStatus.accepted,
      );
      expect(s, MatchStatus.accepted);
    });

    test('...but stays an error when the state is different', () async {
      await expectLater(
        resolveByRefetch<MatchStatus>(
          sleep: _noSleep,
          action: () async => throw _gwm('GWM_MATCH_NOT_FOUND'),
          staleCodes: {'GWM_MATCH_NOT_FOUND'},
          refetchIfDone: () async => null,
        ),
        throwsA(isA<AppFailure>()),
      );
    });
  });
}
