import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/error/app_failure.dart';
import '../../../core/error/failure_messages.dart';
import '../../../core/l10n/strings_dual.dart';
import '../../../core/l10n/strings_r6_cd.dart';
import '../../../core/l10n/strings_roles.dart';
import '../../../core/router/redirect.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/tone.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../matching/presentation/matching_providers.dart' show refreshClockProvider;
import '../../roles/domain/role_state.dart';
import '../../roles/presentation/role_providers.dart';
import '../../trip/domain/dropoff.dart';
import '../../trip/domain/travel_mode.dart';
import '../../trip/presentation/create_trip_widgets.dart' show DropoffLimitControl;
import '../../trip/presentation/trip_providers.dart';
import '../domain/preset.dart';
import '../domain/quick_time.dart';
import 'preset_providers.dart';
import 'quick_home_controller.dart';

/// F-14 "กำลังจะกลับบ้านใช่ไหม?": car trips only (Rider / Driver). Shown on Home when there is no active trip.
/// Missing / partial presets lead to the setup flow; the wizard stays available.
class QuickHomeCard extends ConsumerStatefulWidget {
  const QuickHomeCard({super.key});

  @override
  ConsumerState<QuickHomeCard> createState() => _QuickHomeCardState();
}

class _QuickHomeCardState extends ConsumerState<QuickHomeCard> {
  int? _selected; // minutes since midnight, -1 = now; null = not chosen yet (default applies)
  DateTime? _custom;
  int? _dropoff;
  bool _registerHint = false;
  bool _switchFailed = false;

  DateTime _now() => ref.read(refreshClockProvider)();

  List<TimeOption> _options(DateTime now) {
    final list = quickTimeOptions(now);
    final c = _custom;
    if (c != null && c.isAfter(now) && !list.any((o) => o.minutes == c.hour * 60 + c.minute)) {
      return [...list, TimeOption(c)];
    }
    return list;
  }

  TimeOption _chosen(List<TimeOption> opts, PresetData d) {
    final want = _selected ?? d.lastDepartMinutes ?? -1;
    return opts.firstWhere((o) => o.minutes == want, orElse: () => opts.first);
  }

  Future<void> _pickOther() async {
    final now = _now();
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(now.add(const Duration(minutes: 30))));
    if (t == null || !mounted) return;
    var at = DateTime(now.year, now.month, now.day, t.hour, t.minute);
    if (!at.isAfter(now)) at = at.add(const Duration(days: 1));
    setState(() {
      _custom = at;
      _selected = t.hour * 60 + t.minute;
    });
    ref.read(quickHomeProvider.notifier).clearError();
  }

  Future<void> _setRole(ActiveRole r) async {
    ref.read(quickHomeProvider.notifier).clearError();
    setState(() {
      _registerHint = false;
      _switchFailed = false;
    });
    final out = await ref.read(roleControllerProvider.notifier).switchTo(r);
    if (!mounted) return;
    setState(() {
      _registerHint = out == RoleSwitchOutcome.notRegistered;
      _switchFailed = out == RoleSwitchOutcome.offlineToDriver || out == RoleSwitchOutcome.failed;
    });
    // The role strip may also show its own failure banner: the inline text here is enough.
    if (_switchFailed) ref.read(roleControllerProvider.notifier).dismissSwitchFailure();
  }

  Future<void> _adjustDropoff(int current) async {
    var value = current;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              DropoffLimitControl(
                value: value,
                onChanged: (v) {
                  setSheet(() => value = v);
                  setState(() => _dropoff = v);
                },
              ),
              const SizedBox(height: AppSpacing.md),
              AppButton(label: R6C.dropoffDone, onPressed: () => Navigator.of(ctx).pop()),
            ]),
          ),
        ),
      ),
    );
  }

  Future<void> _create(TimeOption time, ActiveRole role, int dropoff) async {
    final ok = await ref.read(quickHomeProvider.notifier).create(
          departAt: time.at,
          role: role.tripRole,
          maxDropoffM: dropoff,
        );
    if (!ok || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(role == ActiveRole.driver ? R.createdDriver : R.createdRider)));
    context.go(Routes.nearby);
  }

  /// Fallback: the full wizard with what the user already chose (nothing is lost).
  void _openWizard(PresetData d, TimeOption time, ActiveRole role, int dropoff) {
    final f = ref.read(tripFormProvider.notifier)..reset();
    if (d.start != null) f.setOrigin(d.start!.toPlace());
    if (d.home != null) f.setDest(d.home!.toPlace());
    f.setMode(TravelMode.car);
    f.setRole(role.tripRole);
    if (role == ActiveRole.driver) f.setMaxDropoff(dropoff);
    time.at == null ? f.departNow() : f.departAt(time.at!);
    context.push(Routes.tripNew);
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(presetsProvider);
    final d = async.valueOrNull;
    if (d == null) return const SizedBox.shrink();
    if (d.isEmpty) return _missing(context);
    if (!d.isComplete) return _partial(context, d);
    return _ready(context, d);
  }

  Widget _missing(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      container: true,
      label: R6C.quickLandmark,
      child: AppCard(
        key: const Key('quick-missing'),
        tone: AppCardTone.info,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(R6C.missingTitle, style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.xs),
          Row(children: [
            const Icon(Icons.lock_outline, size: 16),
            const SizedBox(width: AppSpacing.xs),
            Expanded(child: Text(R6C.localOnlyCaption, style: TextStyle(color: context.tone.textSecondary))),
          ]),
          const SizedBox(height: AppSpacing.md),
          AppButton(
            key: const Key('quick-setup'),
            label: R6C.missingCta,
            icon: Icons.home_outlined,
            onPressed: () => context.push(Routes.mePlace(PresetKind.home.db)),
          ),
          AppButton(
            key: const Key('quick-wizard'),
            label: R6C.createOwn,
            variant: AppButtonVariant.text,
            onPressed: () => context.push(Routes.tripNew),
          ),
        ]),
      ),
    );
  }

  Widget _partial(BuildContext context, PresetData d) {
    final theme = Theme.of(context);
    final missingHome = d.home == null;
    return AppCard(
      key: const Key('quick-partial'),
      tone: AppCardTone.info,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(R6C.missingTitle, style: theme.textTheme.titleMedium),
        const SizedBox(height: AppSpacing.xs),
        Text(R6C.partialMissing(missingHome ? R6C.homeRow : R6C.startRow)),
        const SizedBox(height: AppSpacing.md),
        AppButton(
          key: const Key('quick-continue-setup'),
          label: R6C.partialCta,
          onPressed: () => context.push(Routes.mePlace((missingHome ? PresetKind.home : PresetKind.start).db)),
        ),
        AppButton(
          key: const Key('quick-wizard'),
          label: R6C.createOwn,
          variant: AppButtonVariant.text,
          onPressed: () => context.push(Routes.tripNew),
        ),
      ]),
    );
  }

  /// Round 9 (US-2/T4, PM ruling #4 in design-spec-round9.md "คำตัดสิน PM"): the default
  /// surface of the ready card must stay minimal — search field + the 2 shortcut chips +
  /// a single primary button, never "a box inside a box". The full time/role/dropoff
  /// selector (previously always inline) now only appears after the user taps the search
  /// field or the primary button, inside a bottom sheet (`_openSelectors`).
  Widget _ready(BuildContext context, PresetData d) {
    final theme = Theme.of(context);
    final quick = ref.watch(quickHomeProvider);
    final creating = quick.creating;
    final routeLabel = R6C.quickRoute(d.start!.name, d.home!.name);
    final tone = context.tone;

    return Semantics(
      container: true,
      label: R6C.quickLandmark,
      child: AppCard(
        key: const Key('quick-home-card'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(R6C.quickTitle, style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.xs),
          Text(routeLabel, key: const Key('quick-route'), style: TextStyle(color: tone.textSecondary)),
          const SizedBox(height: AppSpacing.md),
          Semantics(
            button: true,
            label: R6C.quickSearchSemantics(routeLabel),
            excludeSemantics: true,
            child: InkWell(
              key: const Key('quick-search-field'),
              borderRadius: BorderRadius.circular(AppRadius.pill),
              onTap: creating ? null : () => _openSelectors(context, d),
              child: Container(
                constraints: const BoxConstraints(minHeight: AppSpacing.minTap),
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                decoration: BoxDecoration(
                  color: tone.bg,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  border: Border.all(color: tone.border),
                ),
                child: Row(children: [
                  Icon(Icons.search, size: 20, color: tone.textSecondary),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: Text(R6C.quickSearchPlaceholder, style: TextStyle(color: tone.textSecondary))),
                ]),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(children: [
            Expanded(
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: AppSpacing.minTap),
                child: ActionChip(
                  key: const Key('quick-shortcut-home'),
                  label: const Text(R6C.quickShortcutHome),
                  onPressed: creating ? null : () => context.push(Routes.mePlace(PresetKind.home.db)),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: AppSpacing.minTap),
                child: ActionChip(
                  key: const Key('quick-shortcut-work'),
                  label: const Text(R6C.quickShortcutWork),
                  onPressed: creating ? null : () => context.push(Routes.mePlace(PresetKind.start.db)),
                ),
              ),
            ),
          ]),
          const SizedBox(height: AppSpacing.md),
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: AppButton(
              key: const Key('quick-primary-cta'),
              label: R6C.quickPrimaryCta,
              icon: Icons.groups_2_outlined,
              onPressed: creating ? null : () => _openSelectors(context, d),
            ),
          ),
        ]),
      ),
    );
  }

  /// The previous always-inline selectors (time chip / role segmented / dropoff adjuster /
  /// hints / errors / final create button), now revealed on demand in a sheet. Local fields
  /// (`_selected`, `_dropoff`, `_registerHint`, `_switchFailed`) still live on this State so
  /// the choice survives the sheet closing/reopening; `setSheet` mirrors every change into the
  /// sheet's own rebuild the same way `_adjustDropoff` already does for the dropoff value.
  Future<void> _openSelectors(BuildContext context, PresetData d) async {
    ref.read(quickHomeProvider.notifier).clearError();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(AppSpacing.pageH, 0, AppSpacing.pageH, AppSpacing.xl),
            child: Consumer(
              builder: (ctx, ref, _) => _selectorsBody(ctx, ref, d, setSheet),
            ),
          ),
        ),
      ),
    );
  }

  Widget _selectorsBody(BuildContext context, WidgetRef ref, PresetData d, StateSetter setSheet) {
    final theme = Theme.of(context);
    final quick = ref.watch(quickHomeProvider);
    final role = ref.watch(activeRoleProvider) ?? ActiveRole.rider;
    final now = _now();
    final opts = _options(now);
    final time = _chosen(opts, d);
    final dropoff = clampDropoff(_dropoff ?? d.lastMaxDropoffM ?? dropoffDefaultM);
    final switching = ref.watch(roleControllerProvider.select((s) => s.switching.isSwitching));
    final creating = quick.creating;
    final roleLabel = role == ActiveRole.driver ? R6C.roleDriver : R6C.roleRider;
    final timeLabel = time.isNow ? R6C.timeNow : time.hm;
    final failure = quick.failure;

    void update(VoidCallback fn) {
      setState(fn);
      setSheet(() {});
    }

    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(R6C.quickSelectorsTitle, style: theme.textTheme.titleMedium),
      const SizedBox(height: AppSpacing.md),
      // Time chips (single select, scroll sideways when the text is large).
      Semantics(
        container: true,
        label: R6C.timeGroup,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (final o in opts) ...[
              Semantics(
                label: R6C.timeSemantics(o.isNow ? R6C.timeNow : o.hm, o.minutes == time.minutes),
                excludeSemantics: true,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: AppSpacing.minTap),
                  child: ChoiceChip(
                    key: Key('time-chip-${o.isNow ? 'now' : o.hm}'),
                    label: Text(o.isNow ? R6C.timeNow : o.hm),
                    selected: o.minutes == time.minutes,
                    showCheckmark: true,
                    onSelected: creating
                        ? null
                        : (_) {
                            update(() => _selected = o.minutes);
                            ref.read(quickHomeProvider.notifier).clearError();
                          },
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
            ],
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: AppSpacing.minTap),
              child: ActionChip(
                key: const Key('time-chip-other'),
                avatar: const Icon(Icons.schedule, size: 18),
                label: const Text(R6C.timeOther),
                onPressed: creating
                    ? null
                    : () async {
                        await _pickOther();
                        setSheet(() {});
                      },
              ),
            ),
          ]),
        ),
      ),
      const SizedBox(height: AppSpacing.md),
      // Role = the app-wide active role (P-7): switching changes the tone of the whole app.
      Semantics(
        container: true,
        label: R6C.roleGroup,
        child: SizedBox(
          width: double.infinity,
          child: SegmentedButton<ActiveRole>(
            key: const Key('quick-role'),
            showSelectedIcon: true,
            style: const ButtonStyle(minimumSize: WidgetStatePropertyAll(Size(0, AppSpacing.minTap))),
            segments: const [
              ButtonSegment(value: ActiveRole.rider, icon: Icon(Icons.event_seat), label: Text(R6C.roleRider)),
              ButtonSegment(value: ActiveRole.driver, icon: Icon(Icons.drive_eta), label: Text(R6C.roleDriver)),
            ],
            selected: {role},
            onSelectionChanged: creating || switching
                ? null
                : (s) async {
                    await _setRole(s.first);
                    setSheet(() {});
                  },
          ),
        ),
      ),
      if (role == ActiveRole.driver) ...[
        const SizedBox(height: AppSpacing.sm),
        Row(children: [
          const Icon(Icons.drive_eta, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(R6C.dropoffRow(formatMetres(dropoff)), key: const Key('quick-dropoff'))),
          TextButton(
            key: const Key('quick-dropoff-adjust'),
            style: TextButton.styleFrom(minimumSize: const Size(0, AppSpacing.minTap)),
            onPressed: creating
                ? null
                : () async {
                    await _adjustDropoff(dropoff);
                    setSheet(() {});
                  },
            child: const Text(R6C.dropoffAdjust),
          ),
        ]),
      ],
      if (_registerHint || quick.needsRegister) ...[
        const SizedBox(height: AppSpacing.sm),
        Semantics(
          liveRegion: true,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(quick.needsRegister ? R6C.driverNoVehicle : R6C.driverNeedsRegister, key: const Key('quick-register-hint')),
            TextButton(
              key: const Key('quick-register'),
              style: TextButton.styleFrom(minimumSize: const Size(0, AppSpacing.minTap)),
              onPressed: () => context.push(Routes.driverRegisterFor(returnTo: Routes.home)),
              child: const Text(R6C.driverRegisterLink),
            ),
          ]),
        ),
      ],
      if (_switchFailed) ...[
        const SizedBox(height: AppSpacing.sm),
        Semantics(liveRegion: true, child: Text(D.errSwitch, key: const Key('quick-switch-error'), style: TextStyle(color: context.tone.dangerInk))),
      ],
      const SizedBox(height: AppSpacing.md),
      Semantics(
        button: true,
        label: R6C.quickCtaSemantics(timeLabel, roleLabel),
        excludeSemantics: true,
        onTap: creating ? null : () => _create(time, role, dropoff),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: AppButton(
            key: const Key('quick-cta'),
            label: creating ? R6C.quickCreating : R6C.quickCta,
            icon: Icons.groups_2_outlined,
            loading: creating,
            onPressed: (creating || switching) ? null : () => _create(time, role, dropoff),
          ),
        ),
      ),
      if (failure != null || quick.hasActiveTrip) ...[
        const SizedBox(height: AppSpacing.sm),
        Semantics(
          liveRegion: true,
          child: Text(
            _failureText(failure),
            key: const Key('quick-error'),
            style: TextStyle(color: context.tone.dangerInk),
          ),
        ),
        Wrap(spacing: AppSpacing.sm, children: [
          if (quick.hasActiveTrip)
            TextButton(
              key: const Key('quick-go-active'),
              style: TextButton.styleFrom(minimumSize: const Size(0, AppSpacing.minTap)),
              onPressed: () => context.push(Routes.tripActiveNow),
              child: const Text(R6C.goActiveTrip),
            ),
          TextButton(
            key: const Key('quick-step-by-step'),
            style: TextButton.styleFrom(minimumSize: const Size(0, AppSpacing.minTap)),
            onPressed: () => _openWizard(d, time, role, dropoff),
            child: const Text(R6C.stepByStep),
          ),
        ]),
      ],
    ]);
  }

  String _failureText(AppFailure? f) {
    if (f == null) return failureMessage(const AppFailure('GWM_ACTIVE_TRIP_LIMIT'));
    final network = f.code == FailureCode.networkOffline ||
        f.code == FailureCode.networkTimeout ||
        f.code == FailureCode.serverUnavailable;
    return network ? R6C.quickNetworkError : failureMessage(f);
  }
}
