import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/error/app_failure.dart';
import '../../../core/error/failure_messages.dart';
import '../../../core/error/result.dart';
import '../../../core/l10n/strings_p4.dart';
import '../../../core/l10n/strings_roles.dart';
import '../../../core/l10n/strings_trip.dart';
import '../../../core/map/app_map.dart';
import '../../../core/router/redirect.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/role_badge.dart';
import '../../../core/widgets/state_view.dart';
import '../../avatar/presentation/avatar_providers.dart';
import '../../avatar/presentation/avatar_screens.dart';
import '../../avatar/presentation/user_avatar.dart';
import '../../geo/presentation/pick_point_screen.dart';
import '../../reviews/presentation/review_widgets.dart';
import '../../trip/domain/trip.dart';
import '../../trip/domain/trip_form.dart';
import '../../trip/presentation/live_map_screen.dart' show OpenLiveMapButton;
import '../../trip/presentation/navigate_button.dart';
import '../../trip/presentation/trip_lifecycle_providers.dart' show tripTrackingProvider;
import '../../trip/presentation/trip_providers.dart';
import '../../vehicle/presentation/vehicle_providers.dart';
import '../../vehicle/presentation/vehicle_widgets.dart';
import '../domain/match_models.dart';
import 'car_match_widgets.dart';
import 'matching_providers.dart';
import 'matching_widgets.dart';

/// S-16 + T4.29: partner summary and the meeting-point handshake
/// (one side proposes, the other confirms; PM decision P-2).
class MatchDetailScreen extends ConsumerStatefulWidget {
  const MatchDetailScreen({super.key, required this.matchId});
  final String matchId;

  @override
  ConsumerState<MatchDetailScreen> createState() => _MatchDetailState();
}

class _MatchDetailState extends ConsumerState<MatchDetailScreen> {
  bool _busy = false;

  /// I cancelled this match on this screen (only my own confirmation may say so).
  bool _cancelledByMe = false;

  void _toast(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _run(Future<Result<void>> Function() action, String okText) async {
    if (_busy) return;
    setState(() => _busy = true);
    final res = await action();
    if (!mounted) return;
    setState(() => _busy = false);
    _toast(res.when(ok: (_) => okText, err: failureMessage));
  }

  Future<void> _proposePeer(MatchSummary m) async {
    final place = await Navigator.of(context).push<Place>(
      MaterialPageRoute(
        builder: (_) => PickPointScreen(
          title: T.pickTitleMeeting,
          initial: m.proposedPoint ?? m.meetingPoint,
        ),
      ),
    );
    if (place == null || !mounted) return;
    await _run(
      () => ref.read(inboxProvider.notifier).proposeMeeting(m.id, place.point, place.label),
      T.meetingSaved,
    );
  }

  Future<void> _cancel(MatchSummary m) async {
    final ok = await showConfirmDialog(
      context,
      title: m.isCar ? R.cancelTitle : T.cancelMatchTitle,
      body: !m.isCar ? T.cancelMatchBody : (m.iAmDriver ? R.cancelBodyDriver : R.cancelBodyRider),
      safeLabel: m.isCar ? R.cancelKeep : T.cancelMatchKeep,
      confirmLabel: m.isCar ? R.cancel : T.cancelMatch,
    );
    if (!ok || !mounted) return;
    await _run(() async {
      final res = await ref.read(inboxProvider.notifier).cancel(m.id);
      if (res case Ok()) _cancelledByMe = true;
      return res;
    }, m.isCar ? R.endedByMe : T.matchCancelled);
  }

  Future<void> _propose(MatchSummary m) async {
    if (m.isCar) {
      // S-34: own screen with the route/warning handling.
      await context.push<void>(Routes.pickup(m.id));
      return;
    }
    await _proposePeer(m);
  }

  @override
  Widget build(BuildContext context) {
    final inbox = ref.watch(inboxProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text(T.matchDetail),
        // Fail-safe: a deep link, notification tap, or a redirect elsewhere
        // in the app can land here with an empty back stack (Flutter's
        // auto-back-button only appears when canPop() is true). Never leave
        // the user stranded on this screen with no way out.
        leading: context.canPop()
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: P.backHome,
                onPressed: () => context.go(Routes.home),
              ),
      ),
      body: inbox.when(
        loading: () => const StateView.loading(),
        error: (e, _) => StateView.failure(
          e is AppFailure ? e : const AppFailure(FailureCode.unknown),
          onRetry: () => ref.invalidate(inboxProvider),
        ),
        data: (all) {
          MatchSummary? m;
          for (final x in all) {
            if (x.id == widget.matchId) m = x;
          }
          if (m == null) {
            return StateView.empty(
              icon: Icons.link_off,
              title: T.closedRequest,
              actionLabel: T.matchesTitle,
              onAction: () => context.go(Routes.chats),
            );
          }
          return _body(m);
        },
      ),
    );
  }

  Widget _body(MatchSummary m) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    if (m.isCar) return _carBody(m);
    final open = m.status == MatchStatus.accepted;
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.pageH),
      children: [
        Center(child: _partnerAvatar(m)),
        const SizedBox(height: AppSpacing.md),
        Text(m.displayName, style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
        const SizedBox(height: AppSpacing.sm),
        Center(child: BadgeWrap(m.badges)),
        if (m.mode != null && m.departAt != null) ...[
          const SizedBox(height: AppSpacing.md),
          Center(child: Text('${m.mode!.label} · ${formatDeparture(m.departAt!, now)}')),
        ],
        const SizedBox(height: AppSpacing.xl),
        if (!open)
          const AppCard(tone: AppCardTone.warning, child: Text(T.closedRequest))
        else ...[
          AppButton(
            label: 'เปิดแชท',
            icon: Icons.chat_bubble_outline,
            onPressed: () => context.push(Routes.chat(m.id)),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(T.meetingPoint, style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          _meeting(m),
          const SizedBox(height: AppSpacing.lg),
          const AppCard(tone: AppCardTone.warning, child: Text(T.publicPlaceWarning)),
        ],
        if (m.status == MatchStatus.accepted || m.status == MatchStatus.pending) ...[
          const SizedBox(height: AppSpacing.xl),
          AppButton(
            label: T.cancelMatch,
            variant: AppButtonVariant.secondary,
            onPressed: _busy ? null : () => _cancel(m),
          ),
        ],
      ],
    );
  }

  /// L avatar (96): photo for a matched partner (tap = viewer + report), initials otherwise (E-1).
  Widget _partnerAvatar(MatchSummary m) => UserAvatar.partner(
        key: const Key('match-avatar'),
        name: m.displayName,
        matchId: m.id,
        size: 96,
        onTap: (m.partnerId == null || !matchMayShowPhoto(m))
            ? null
            : () => showPartnerPhotoSheet(context, matchId: m.id, partnerId: m.partnerId!, name: m.displayName, role: m.partnerRole),
      );

  /// US-23/24/26 extras of an accepted match: shared map, one navigation button, review prompt.
  List<Widget> _roundFiveExtras(MatchSummary m, Trip? myTrip) {
    final inProgress = myTrip?.status == TripStatus.inProgress && m.status == MatchStatus.accepted;
    final myPos = ref.watch(tripTrackingProvider).fix?.point;
    return [
      if (inProgress) ...[
        const SizedBox(height: AppSpacing.md),
        OpenLiveMapButton(matchId: m.id),
        if (myTrip != null) ...[
          const SizedBox(height: AppSpacing.sm),
          NavigateButton(trip: myTrip, match: m, myPosition: myPos),
        ],
      ],
      if (m.isCar && m.boarded) ...[
        const SizedBox(height: AppSpacing.md),
        ReviewPromptCard(match: m),
      ],
    ];
  }

  /// S-16 for car matches: role badge, vehicle (Rider) / vehicle preview
  /// (Driver), consent status, pickup card, progress, cancel rules.
  Widget _carBody(MatchSummary m) {
    final theme = Theme.of(context);
    final trip = ref.watch(activeTripProvider).valueOrNull;
    final myTrip = trip != null && trip.id == m.myTripId ? trip : null;
    final accepted = m.status == MatchStatus.accepted;
    final ended = m.status == MatchStatus.cancelled;
    final now = DateTime.now();
    // Q-2: a Rider who boarded keeps seeing the vehicle even after the match ended.
    final vehicleVisible = m.iAmRider && (accepted || (ended && m.boarded));
    final late = m.iAmRider &&
        accepted &&
        m.partnerTripStatus == TripStatus.scheduled &&
        m.departAt != null &&
        now.isAfter(m.departAt!);

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.pageH),
      children: [
        Center(child: _partnerAvatar(m)),
        const SizedBox(height: AppSpacing.md),
        Text(m.displayName, style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
        const SizedBox(height: AppSpacing.sm),
        if (m.partnerRole != null) Center(child: RoleRow(m.partnerRole!)),
        if (m.partnerId != null && m.partnerRole != null)
          Center(child: RatingSummary(userId: m.partnerId!, role: m.partnerRole!)),
        const SizedBox(height: AppSpacing.sm),
        Center(child: BadgeWrap(m.badges)),
        const SizedBox(height: AppSpacing.lg),
        if (ended)
          MatchEndNotice(
            byMe: _cancelledByMe,
            backToSearch: myTrip?.status == TripStatus.scheduled && !m.boarded,
            driverContinues: m.iAmDriver && myTrip?.status == TripStatus.inProgress,
          )
        else if (!accepted)
          const AppCard(tone: AppCardTone.warning, child: Text(R.requestClosed)),
        if (late) ...[
          const AppCard(
            tone: AppCardTone.warning,
            child: Text(R.driverLate, key: Key('driver-late')),
          ),
        ],
        if (ended && m.isCar && m.boarded) ...[
          const SizedBox(height: AppSpacing.md),
          ReviewPromptCard(match: m),
        ],
        const SizedBox(height: AppSpacing.md),
        if (m.iAmRider) ..._riderVehicle(m, vehicleVisible, accepted, ended),
        if (m.iAmDriver && accepted) ..._driverVehicle(),
        if (accepted) ...[
          const SizedBox(height: AppSpacing.md),
          PickupPointCard(
            match: m,
            editable: pickupEditable(m, myTripStatus: myTrip?.status),
            busy: _busy,
            onPropose: () => _propose(m),
            onConfirm: () => _run(
              () => ref.read(inboxProvider.notifier).confirmMeeting(m.id),
              T.meetingConfirmed,
            ),
          ),
          ..._roundFiveExtras(m, myTrip),
          const SizedBox(height: AppSpacing.md),
          TripProgressRow(match: m, myTripStatus: myTrip?.status),
          const SizedBox(height: AppSpacing.lg),
          AppButton(
            label: 'เปิดแชท',
            icon: Icons.chat_bubble_outline,
            onPressed: () => context.push(Routes.chat(m.id)),
          ),
          const SizedBox(height: AppSpacing.md),
          if (m.boarded)
            // R3-3: nothing to cancel any more; the trip ends with "ถึงแล้ว".
            const Text(R.cannotCancelMatchAfterBoarded, key: Key('no-cancel-after-boarded'))
          else
            AppButton(
              key: const Key('cancel-match'),
              label: R.cancel,
              variant: AppButtonVariant.secondary,
              onPressed: _busy ? null : () => _cancel(m),
            ),
        ],
      ],
    );
  }

  List<Widget> _riderVehicle(MatchSummary m, bool visible, bool accepted, bool ended) {
    if (!visible) {
      return [
        if (ended) const AppCard(child: Text(R.vehicleEnded, key: Key('vehicle-ended'))),
      ];
    }
    final v = ref.watch(matchVehicleProvider(m.id));
    return [
      v.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => VehicleLoadError(onRetry: () => ref.invalidate(matchVehicleProvider(m.id))),
        data: (view) => view == null
            ? const AppCard(child: Text(R.vehicleEnded, key: Key('vehicle-ended')))
            : VehicleInfoCard.forRider(view, highlight: _justMatched(m) ? R.justMatched : null),
      ),
      if (accepted) ShareConsentStatus(view: v),
    ];
  }

  bool _justMatched(MatchSummary m) => DateTime.now().difference(m.createdAt).inMinutes < 60 && !m.boarded;

  List<Widget> _driverVehicle() {
    final mine = ref.watch(myVehicleProvider).valueOrNull;
    return [
      if (mine != null) VehicleInfoCard.ownerPreview(mine),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          key: const Key('edit-vehicle-link'),
          onPressed: () => context.push(Routes.vehicleFor()),
          child: const Text(R.editVehicle),
        ),
      ),
    ];
  }

  Widget _meeting(MatchSummary m) {
    final agreed = m.meetingPoint;
    final proposed = m.proposedPoint;
    if (proposed != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(m.proposedByMe ? T.meetingWaiting : T.meetingProposedByPartner,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: AppSpacing.xs),
          Text(m.proposedLabel ?? ''),
          const SizedBox(height: AppSpacing.sm),
          _miniMap(proposed),
          const SizedBox(height: AppSpacing.md),
          if (m.hasProposalFromPartner)
            AppButton(
              label: T.meetingConfirm,
              variant: AppButtonVariant.success,
              loading: _busy,
              onPressed: () => _run(
                () => ref.read(inboxProvider.notifier).confirmMeeting(m.id),
                T.meetingConfirmed,
              ),
            ),
          AppButton(
            label: T.meetingChange,
            variant: AppButtonVariant.secondary,
            onPressed: _busy ? null : () => _propose(m),
          ),
        ],
      );
    }
    if (agreed != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(m.meetingLabel ?? ''),
          const SizedBox(height: AppSpacing.sm),
          _miniMap(agreed),
          const SizedBox(height: AppSpacing.md),
          AppButton(
            label: T.meetingChange,
            variant: AppButtonVariant.secondary,
            onPressed: _busy ? null : () => _propose(m),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(T.meetingNone),
        const SizedBox(height: AppSpacing.md),
        AppButton(label: T.meetingPropose, loading: _busy, onPressed: () => _propose(m)),
      ],
    );
  }

  Widget _miniMap(LatLng point) => SizedBox(
        height: 180,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.card),
          child: AppMap(
            center: point,
            zoom: 16,
            pins: [MapPin(point: point, icon: Icons.place, color: AppColors.danger)],
            showZoomButtons: false,
          ),
        ),
      );
}
