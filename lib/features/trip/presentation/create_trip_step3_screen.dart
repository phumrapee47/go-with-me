import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/error/app_failure.dart';
import '../../../core/error/failure_messages.dart';
import '../../../core/l10n/strings_dual.dart';
import '../../../core/l10n/strings_roles.dart';
import '../../../core/l10n/strings_trip.dart';
import '../../../core/map/app_map.dart';
import '../../../core/router/redirect.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/tone.dart';
import '../../../core/theme/tone_scope.dart';
import '../../../core/widgets/app_card.dart';
import '../../geo/domain/geo_services.dart';
import '../../push/presentation/push_permission_sheet.dart';
import '../../roles/presentation/role_providers.dart';
import '../../vehicle/presentation/vehicle_providers.dart';
import '../domain/travel_mode.dart';
import '../domain/trip.dart';
import '../domain/trip_form.dart';
import 'create_trip_widgets.dart';
import 'trip_providers.dart';
import 'trip_tone.dart';

/// S-12: route preview via OSRM, summary, create. Route failure is fail-closed:
/// the create button stays disabled (an estimated straight line would corrupt
/// the overlap score, design-api 9.3).
class CreateTripStep3Screen extends ConsumerStatefulWidget {
  const CreateTripStep3Screen({super.key, this.clock = DateTime.now});
  final DateTime Function() clock;

  @override
  ConsumerState<CreateTripStep3Screen> createState() => _Step3State();
}

class _Step3State extends ConsumerState<CreateTripStep3Screen> {
  bool _submitting = false;
  AppFailure? _saveError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final f = ref.read(tripFormProvider);
      final incomplete = TripFormValidator.validatePlaces(f.origin, f.dest) != null || f.mode == null;
      if (incomplete && mounted) context.go(Routes.tripNew);
    });
  }

  Future<void> _submit(RouteResult route) async {
    if (_submitting) return;
    final f = ref.read(tripFormProvider);
    final now = widget.clock();
    final issue = TripFormValidator.validateOptions(
      mode: f.mode,
      departAt: f.scheduledAt,
      now: now,
      role: f.role,
      hasVehicle: ref.read(myVehicleProvider).valueOrNull != null,
    );
    if (issue != null) {
      setState(() => _saveError = switch (issue) {
            TripFormIssue.roleMissing => const AppFailure('GWM_ROLE_REQUIRED'),
            TripFormIssue.vehicleMissing => const AppFailure('GWM_VEHICLE_REQUIRED'),
            _ => const AppFailure('GWM_DEPART_IN_PAST'),
          });
      return;
    }
    setState(() {
      _submitting = true;
      _saveError = null;
    });
    final draft = TripDraft(
      id: f.draftId,
      mode: f.mode!,
      origin: f.origin!,
      dest: f.dest!,
      route: route.geometry,
      distanceM: route.distanceM,
      durationS: route.durationS,
      departAt: f.departAt(now),
      role: f.mode == TravelMode.car ? f.role : null,
      maxDropoffM: f.mode == TravelMode.car && f.role == TripRole.driver ? f.maxDropoffM : null,
      detourToleranceM: f.mode == TravelMode.car && f.role == TripRole.driver ? f.detourToleranceM : null,
      vibeTags: f.vibeTags,
      moodText: f.moodText,
      womenOnly: f.womenOnly,
    );
    final res = await ref.read(tripRepositoryProvider).createTrip(draft);
    if (!mounted) return;
    res.when(
      ok: (_) {
        ref.invalidate(activeTripProvider);
        ref.read(tripFormProvider.notifier).reset();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(switch (draft.role) {
            TripRole.driver => R.createdDriver,
            TripRole.rider => R.createdRider,
            null => T.tripCreated,
          }),
        ));
        _afterCreate(context, ref);
      },
      err: (failure) {
        // Registration lost elsewhere (F-D8): fall back to the server's view of the role state.
        if (failure.code == 'GWM_NOT_A_DRIVER') ref.read(roleControllerProvider.notifier).refresh();
        setState(() {
          _submitting = false;
          _saveError = failure;
        });
      },
    );
  }

  /// US-42 (G.1.1 step 1): first trip creation is the other trigger for the
  /// push permission sheet (a no-op if already asked at login).
  Future<void> _afterCreate(BuildContext context, WidgetRef ref) async {
    await maybeShowPushPermissionSheet(context, ref);
    if (context.mounted) context.go(Routes.nearby);
  }

  @override
  Widget build(BuildContext context) {
    final form = ref.watch(tripFormProvider);
    if (form.origin == null || form.dest == null || form.mode == null) {
      return const Scaffold(body: SizedBox.shrink());
    }
    final route = ref.watch(routePreviewProvider);
    final now = widget.clock();
    final theme = Theme.of(context);

    return ToneScope(
      tone: toneOfTripRole(form.mode == TravelMode.car ? form.role : null),
      child: Scaffold(
      appBar: AppBar(title: const Text(T.confirmTitle)),
      body: Column(
        children: [
          const StepIndicator(step: 3),
          SizedBox(
            height: 240,
            child: AppMap(
              center: form.origin!.point,
              route: route.valueOrNull?.geometry ?? const [],
              pins: [
                MapPin(point: form.origin!.point, icon: Icons.trip_origin, color: AppColors.blue),
                MapPin(point: form.dest!.point, icon: Icons.place, color: AppColors.danger),
              ],
              showZoomButtons: false,
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.pageH),
              children: [
                _routeCard(route, theme),
                const SizedBox(height: AppSpacing.md),
                _row(T.rowFrom, form.origin!.label),
                _row(T.rowTo, form.dest!.label),
                _row(T.rowTime, form.isNow ? T.departNow : formatDeparture(form.scheduledAt!, now)),
                _row(T.rowMode, form.mode!.label),
                if (form.mode == TravelMode.car && form.role != null) ...[
                  // F-D11: the role of THIS trip, large, before it can no longer be changed.
                  Semantics(
                    label: D.confirmRow(form.role!.label),
                    child: Container(
                      key: const Key('confirm-role-row'),
                      margin: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                      padding: const EdgeInsets.all(AppSpacing.md),
                      decoration: BoxDecoration(
                        color: context.tone.infoBg,
                        borderRadius: BorderRadius.circular(AppRadius.card),
                        border: Border.all(color: context.tone.borderStrong),
                      ),
                      child: Row(children: [
                        Icon(form.role!.icon, color: context.tone.accentInk),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(child: Text(D.confirmRow(form.role!.label), style: theme.textTheme.titleMedium)),
                      ]),
                    ),
                  ),
                  _row('', form.role == TripRole.driver ? R.rowSummaryDriver : R.rowSummaryRider),
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xs),
                    child: Text(R.roleLockedNote, style: TextStyle(color: context.tone.textSecondary)),
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                const AppCard(tone: AppCardTone.info, child: Text(T.privacyNote)),
                if (_saveError != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  AppCard(
                    tone: AppCardTone.error,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(failureMessage(_saveError!)),
                        if (const {
                          'GWM_ROLE_REQUIRED',
                          'GWM_ROLE_NOT_ALLOWED',
                          'GWM_NOT_A_DRIVER',
                          'GWM_VEHICLE_REQUIRED',
                          'GWM_VEHICLE_INVALID',
                        }.contains(_saveError!.code))
                          TextButton(
                            key: const Key('back-to-fix'),
                            onPressed: () => context.canPop() ? context.pop() : context.go(Routes.tripOptions),
                            child: const Text(R.backToFix),
                          ),
                        if (_saveError!.code == 'GWM_NOT_A_DRIVER')
                          TextButton(
                            key: const Key('error-register'),
                            onPressed: () => context.push(Routes.driverRegisterFor(returnTo: Routes.tripOptions)),
                            child: const Text(D.gateCta),
                          ),
                        if (_saveError!.code == 'GWM_ACTIVE_TRIP_LIMIT')
                          TextButton(
                            onPressed: () => context.go(Routes.trips),
                            child: const Text(T.goMyTrips),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          FlowBottomBar(
            label: T.createTrip,
            loading: _submitting,
            onPressed: route.hasValue && !route.isLoading ? () => _submit(route.value!) : null,
          ),
        ],
      ),
    ));
  }

  Widget _routeCard(AsyncValue<RouteResult> route, ThemeData theme) {
    return route.when(
      loading: () => const AppCard(
        child: Row(children: [
          SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
          SizedBox(width: AppSpacing.md),
          Text(T.calculatingRoute),
        ]),
      ),
      error: (e, _) {
        final f = e is AppFailure ? e : const AppFailure(FailureCode.serverUnavailable, retryable: true);
        final noRoute = f.code == FailureCode.routeNotFound;
        return AppCard(
          tone: AppCardTone.error,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(noRoute ? failureMessage(f) : T.routeFailed),
              if (!noRoute)
                TextButton(
                  onPressed: () => ref.invalidate(routePreviewProvider),
                  child: const Text('ลองอีกครั้ง'),
                ),
            ],
          ),
        );
      },
      data: (r) => AppCard(
        tone: AppCardTone.info,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(formatRouteSummary(r.distanceM, r.durationS), style: theme.textTheme.titleMedium),
            Text(T.routeEstimate, style: theme.textTheme.bodyMedium?.copyWith(color: context.tone.textSecondary)),
          ],
        ),
      ),
    );
  }

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 56, child: Text(k, style: TextStyle(color: context.tone.textSecondary))),
            Expanded(child: Text(v, maxLines: 2, overflow: TextOverflow.ellipsis)),
          ],
        ),
      );
}
