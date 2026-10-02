import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

import '../../auth/presentation/auth_providers.dart';
import '../../matching/domain/match_models.dart';
import '../../matching/presentation/matching_providers.dart';
import '../../vehicle/presentation/vehicle_providers.dart';
import '../data/supabase_trip_share_repository.dart';
import '../domain/share_companion.dart';
import '../domain/trip_share.dart';

final tripShareRepositoryProvider = Provider<TripShareRepository>(
  (ref) => SupabaseTripShareRepository(Supabase.instance.client),
);

/// Base URL of the public share page (T4.24, P1). Empty = no web page yet, so
/// no link is ever created or shown: only the plain-text snapshot is offered
/// (PM P-5). Set with `--dart-define=SHARE_WEB_BASE_URL=https://...`.
final shareWebBaseUrlProvider = Provider<String>((ref) => const String.fromEnvironment('SHARE_WEB_BASE_URL'));

/// Backend share links that can still be revoked. Empty without a web page.
final activeSharesProvider = FutureProvider<List<ActiveShare>>((ref) async {
  if (ref.watch(authUserProvider.select((a) => a.valueOrNull?.id)) == null) return const [];
  if (ref.watch(shareWebBaseUrlProvider).isEmpty) return const [];
  final res = await ref.watch(tripShareRepositoryProvider).active();
  return res.when(ok: (l) => l, err: (f) => throw f);
});

/// The car-match partner that should appear in a share/SOS text for [tripId]
/// (null-object [ShareCompanion.none] when there is none). Re-read every time
/// a page using it opens (autoDispose) and when the inbox changes (Q-10: no
/// chat message, the switch state is just refreshed quietly).
///
/// A Rider's text carries the Driver's name and, only when the Driver allows
/// it (server flag from `get_match_vehicle`), the plate. Never model/colour.
/// A load failure never blocks: it degrades to "name only".
final shareCompanionProvider = FutureProvider.autoDispose.family<ShareCompanion, String>((ref, tripId) async {
  final inbox = ref.watch(inboxProvider).valueOrNull ?? const <MatchSummary>[];
  MatchSummary? m;
  for (final x in inbox) {
    // An ended match whose Rider had boarded still counts (Q-2 / T6.15 note);
    // one that ended before boarding has no driver section (F-R11.6).
    final live = x.status == MatchStatus.accepted || (x.boarded && x.status == MatchStatus.cancelled);
    if (x.myTripId == tripId && x.isCar && live) m = x;
  }
  if (m == null) return const ShareCompanion.none();
  if (m.iAmRider) {
    try {
      // Straight to the repository (no cache): every recompute is a fresh read
      // of the Driver's switch, which is what makes the send-time re-check real.
      final res = await ref.read(vehicleRepositoryProvider).forMatch(m.id);
      final v = res.when(ok: (v) => v, err: (f) => throw f);
      if (v == null) return ShareCompanion.rider(partnerName: m.displayName);
      return ShareCompanion.rider(
        partnerName: m.displayName,
        plate: v.shareAllowed ? v.plate : null,
        plateAllowed: v.shareAllowed,
      );
    } catch (_) {
      return ShareCompanion.rider(partnerName: m.displayName, statusKnown: false);
    }
  }
  try {
    final res = await ref.read(vehicleRepositoryProvider).mine();
    final mine = res.when(ok: (v) => v, err: (f) => throw f);
    return ShareCompanion.driver(partnerName: m.displayName, plate: mine?.plate);
  } catch (_) {
    return ShareCompanion.driver(partnerName: m.displayName);
  }
});
