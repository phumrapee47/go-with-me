import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/strings_trip.dart';
import '../../../core/router/redirect.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/tone.dart';
import '../../../core/widgets/state_view.dart';
import '../../geo/domain/location_service.dart';
import '../../geo/presentation/current_location.dart';
import '../../geo/presentation/geo_providers.dart';
import '../../geo/presentation/pick_point_screen.dart';
import '../../geo/presentation/place_search_field.dart';
import '../domain/trip.dart';
import '../domain/trip_form.dart';
import 'create_trip_widgets.dart';
import 'trip_providers.dart';

/// S-10: destination + origin. Denying location never blocks the flow.
class CreateTripStep1Screen extends ConsumerStatefulWidget {
  const CreateTripStep1Screen({super.key});

  @override
  ConsumerState<CreateTripStep1Screen> createState() => _Step1State();
}

class _Step1State extends ConsumerState<CreateTripStep1Screen> {
  // BUG-3 (round 8): validation used to be recomputed only inside `_next()`,
  // so origin/dest changes coming from search, GPS, or the map-pin flow never
  // cleared a stale "select origin" error. Recomputing it every `build()`
  // (which already watches `tripFormProvider`) makes it reactive for all 3
  // entry points at once. `_touched` keeps the error hidden until the user
  // has pressed "next" at least once, so a freshly-opened screen never shows
  // a false-positive error before any interaction.
  bool _touched = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _prefillOrigin());
  }

  // Default origin = current position, but ONLY if permission was already
  // granted; this never triggers the OS prompt by itself.
  Future<void> _prefillOrigin() async {
    if (ref.read(tripFormProvider).origin != null) return;
    final loc = ref.read(locationServiceProvider);
    if (await loc.permission() != LocationPermissionState.granted) return;
    final r = await loc.currentPosition();
    final p = r.when(ok: (p) => p, err: (_) => null);
    if (p == null || !mounted || ref.read(tripFormProvider).origin != null) return;
    final label = await labelFor(ref, p);
    if (!mounted || ref.read(tripFormProvider).origin != null) return;
    ref.read(tripFormProvider.notifier).setOrigin(Place(point: p, label: label));
  }

  Future<void> _useCurrent() async {
    final p = await obtainCurrentLocation(context, ref);
    if (p == null || !mounted) return;
    final label = await labelFor(ref, p);
    if (!mounted) return;
    ref.read(tripFormProvider.notifier).setOrigin(Place(point: p, label: label));
  }

  Future<void> _pick({required bool origin}) async {
    final form = ref.read(tripFormProvider);
    final initial = (origin ? form.origin : form.dest)?.point ?? form.origin?.point;
    final place = await Navigator.of(context).push<Place>(
      MaterialPageRoute(
        builder: (_) => PickPointScreen(
          title: origin ? T.pickTitleOrigin : T.pickTitleDest,
          initial: initial,
        ),
      ),
    );
    if (place == null) return;
    final ctrl = ref.read(tripFormProvider.notifier);
    origin ? ctrl.setOrigin(place) : ctrl.setDest(place);
  }

  void _next() {
    final f = ref.read(tripFormProvider);
    final issue = TripFormValidator.validatePlaces(f.origin, f.dest);
    setState(() => _touched = true);
    if (issue == null) context.push(Routes.tripOptions);
  }

  String? _issueText(TripFormIssue? issue) => switch (issue) {
        TripFormIssue.originMissing => T.errOriginMissing,
        TripFormIssue.destMissing => T.errDestMissing,
        TripFormIssue.tooClose => T.errTooClose,
        _ => null,
      };

  @override
  Widget build(BuildContext context) {
    final form = ref.watch(tripFormProvider);
    final active = ref.watch(activeTripProvider);
    final ctrl = ref.read(tripFormProvider.notifier);

    Widget body = active.when(
      loading: () => const StateView.loading(),
      error: (e, _) => StateView.error(
        title: 'ตรวจสอบทริปของคุณไม่สำเร็จ',
        onAction: () => ref.invalidate(activeTripProvider),
      ),
      data: (trip) {
        if (trip != null) return const ActiveTripBlocked();
        final issue =
            _touched ? TripFormValidator.validatePlaces(form.origin, form.dest) : null;
        final issueText = _issueText(issue);
        return Column(
          children: [
            const StepIndicator(step: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pageH),
                children: [
                  PlaceSearchField(
                    key: const ValueKey('dest-field'),
                    label: T.toLabel,
                    place: form.dest,
                    onSelected: ctrl.setDest,
                    onCleared: ctrl.clearDest,
                    onPickOnMap: () => _pick(origin: false),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  PlaceSearchField(
                    key: const ValueKey('origin-field'),
                    label: T.fromLabel,
                    place: form.origin,
                    onSelected: ctrl.setOrigin,
                    onCleared: ctrl.clearOrigin,
                    onPickOnMap: () => _pick(origin: true),
                    onUseCurrent: _useCurrent,
                  ),
                  if (issueText != null)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.md),
                      child: Text(issueText, style: TextStyle(color: context.tone.dangerInk)),
                    ),
                ],
              ),
            ),
            FlowBottomBar(label: 'ถัดไป', onPressed: _next),
          ],
        );
      },
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text(T.newTripTitle),
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'ปิด',
          onPressed: () {
            ctrl.reset();
            context.go(Routes.home);
          },
        ),
      ),
      body: body,
    );
  }
}
