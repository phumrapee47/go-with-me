import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/strings_dual.dart';
import '../../../core/l10n/strings_roles.dart';
import '../../../core/l10n/strings_trip.dart';
import '../../../core/router/redirect.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/tone.dart';
import '../../../core/theme/tone_scope.dart';
import '../../../core/widgets/role_badge.dart';
import '../../roles/domain/role_state.dart';
import '../../roles/presentation/role_providers.dart';
import '../../vehicle/presentation/vehicle_providers.dart';
import '../domain/travel_mode.dart';
import '../domain/trip.dart';
import '../domain/trip_form.dart';
import '../domain/vibe_mood.dart';
import 'create_trip_widgets.dart';
import 'role_picker.dart';
import 'safety_filter_switch.dart';
import 'trip_providers.dart';
import 'trip_tone.dart';
import 'vibe_mood_widgets.dart';

/// S-11: departure time (now / scheduled, never in the past) + ONE travel mode.
class CreateTripStep2Screen extends ConsumerStatefulWidget {
  const CreateTripStep2Screen({super.key, this.clock = DateTime.now});

  /// Injectable for tests.
  final DateTime Function() clock;

  @override
  ConsumerState<CreateTripStep2Screen> createState() => _Step2State();
}

class _Step2State extends ConsumerState<CreateTripStep2Screen> {
  TripFormIssue? _issue;

  @override
  void initState() {
    super.initState();
    // Deep link / process restore without step 1 data: go back to step 1.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final f = ref.read(tripFormProvider);
      if (TripFormValidator.validatePlaces(f.origin, f.dest) != null && mounted) {
        context.go(Routes.tripNew);
      }
    });
  }

  Future<void> _pickTime({required bool tomorrow}) async {
    final now = widget.clock();
    final current = ref.read(tripFormProvider).scheduledAt ?? now;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
    );
    if (t == null || !mounted) return;
    final base = DateTime(now.year, now.month, now.day).add(Duration(days: tomorrow ? 1 : 0));
    final at = DateTime(base.year, base.month, base.day, t.hour, t.minute);
    ref.read(tripFormProvider.notifier).departAt(at);
    setState(() => _issue = null);
  }

  void _next() {
    final f = ref.read(tripFormProvider);
    final issue = TripFormValidator.validateOptions(
      mode: f.mode,
      departAt: f.scheduledAt,
      now: widget.clock(),
      role: f.role,
      hasVehicle: ref.read(myVehicleProvider).valueOrNull != null,
    );
    setState(() => _issue = issue);
    if (issue == null) context.push(Routes.tripConfirm);
  }

  /// Car needs an explicit role, and a Driver needs a vehicle (gate before step 3).
  bool _canNext(TripFormState f) {
    if (f.mode == null) return false;
    if (f.mode != TravelMode.car) return true;
    if (f.role == null) return false;
    if (f.role == TripRole.driver) return ref.watch(myVehicleProvider).valueOrNull != null;
    return true;
  }

  String? _issueText() => switch (_issue) {
        TripFormIssue.departInPast => T.errDepartPast,
        TripFormIssue.modeMissing => T.errModeMissing,
        TripFormIssue.roleMissing => R.roleRequired,
        TripFormIssue.vehicleMissing => R.needsVehicle,
        _ => null,
      };

  @override
  Widget build(BuildContext context) {
    final form = ref.watch(tripFormProvider);
    final ctrl = ref.read(tripFormProvider.notifier);
    final theme = Theme.of(context);
    final now = widget.clock();
    // US-20: a car trip starts on the role of the active mode unless the user chose one themselves.
    final activeRole = ref.watch(activeRoleProvider);
    final registered = ref.watch(driverRegisteredProvider);
    if (form.mode == TravelMode.car) {
      final desired = resolveTripRole(
        activeRole: activeRole,
        registered: registered == true || (registered == null && form.roleTouched),
        roleTouched: form.roleTouched,
        current: form.role,
      );
      if (desired != form.role) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) ctrl.setDefaultRole(desired);
        });
      }
    }
    final scheduledTomorrow = form.scheduledAt != null &&
        DateTime(form.scheduledAt!.year, form.scheduledAt!.month, form.scheduledAt!.day)
                .difference(DateTime(now.year, now.month, now.day))
                .inDays >=
            1;

    // The form takes the tone of the role being created (D.2), with a badge saying so.
    final creatingRole = form.mode == TravelMode.car ? form.role : null;
    return ToneScope(
      tone: toneOfTripRole(creatingRole),
      child: Scaffold(
      appBar: AppBar(
        title: const Text(T.newTripTitle),
        actions: [
          if (creatingRole != null)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.md),
              child: Semantics(
                label: D.tripCreatingAs(creatingRole.label),
                child: RoleBadge(creatingRole, key: const Key('creating-role-badge')),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          const StepIndicator(step: 2),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.pageH),
              children: [
                Text(T.departQuestion, style: theme.textTheme.titleMedium),
                const SizedBox(height: AppSpacing.md),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: true, label: Text(T.departNow)),
                    ButtonSegment(value: false, label: Text(T.departSchedule)),
                  ],
                  selected: {form.isNow},
                  onSelectionChanged: (s) {
                    if (s.first) {
                      ctrl.departNow();
                      setState(() => _issue = null);
                    } else {
                      _pickTime(tomorrow: false);
                    }
                  },
                ),
                if (!form.isNow) ...[
                  const SizedBox(height: AppSpacing.md),
                  Wrap(
                    spacing: AppSpacing.sm,
                    children: [
                      ChoiceChip(
                        label: const Text(T.today),
                        selected: !scheduledTomorrow,
                        onSelected: (_) => _pickTime(tomorrow: false),
                      ),
                      ChoiceChip(
                        label: const Text(T.tomorrow),
                        selected: scheduledTomorrow,
                        onSelected: (_) => _pickTime(tomorrow: true),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    formatDeparture(form.scheduledAt!, now),
                    key: const ValueKey('depart-label'),
                    style: theme.textTheme.titleMedium,
                  ),
                ],
                const SizedBox(height: AppSpacing.xl),
                Text(T.modeQuestion, style: theme.textTheme.titleMedium),
                const SizedBox(height: AppSpacing.xs),
                Text(T.modeHelper, style: theme.textTheme.bodyMedium?.copyWith(color: context.tone.textSecondary)),
                const SizedBox(height: AppSpacing.md),
                // Two per row; each row is as tall as its tallest card, so long
                // labels and large text never overflow (no fixed height).
                for (var i = 0; i < TravelMode.values.length; i += 2)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.md),
                    child: IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final m in TravelMode.values.skip(i).take(2)) ...[
                            if (m != TravelMode.values[i]) const SizedBox(width: AppSpacing.md),
                            Expanded(
                              child: _ModeCard(
                                mode: m,
                                selected: form.mode == m,
                                onTap: () {
                                  ctrl.setMode(m);
                                  setState(() => _issue = null);
                                },
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                if (form.mode == TravelMode.car) ...[
                  const SizedBox(height: AppSpacing.xl),
                  RolePicker(
                    role: form.role,
                    prefilled: !form.roleTouched,
                    showRequiredError: _issue == TripFormIssue.roleMissing,
                    onChanged: (r) {
                      ctrl.setRole(r);
                      setState(() => _issue = null);
                    },
                  ),
                  if (form.role == TripRole.driver) ...[
                    const SizedBox(height: AppSpacing.xl),
                    DropoffLimitControl(value: form.maxDropoffM, onChanged: ctrl.setMaxDropoff),
                    const SizedBox(height: AppSpacing.xl),
                    DetourToleranceControl(value: form.detourToleranceM, onChanged: ctrl.setDetourTolerance),
                  ],
                ],
                if (_issueText() != null && _issue != TripFormIssue.roleMissing)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.md),
                    child: Text(_issueText()!, style: TextStyle(color: context.tone.dangerInk)),
                  ),
                const SizedBox(height: AppSpacing.xl),
                // Progressive disclosure (UX pass): vibe tags, mood, and the women-only switch are
                // all optional and non-blocking, so they start collapsed — a foot/bike/motorbike
                // trip now only ever shows depart-time + mode on this screen by default.
                _OptionalSettingsPanel(
                  hasContent: form.vibeTags.isNotEmpty || form.moodText.isNotEmpty || form.womenOnly,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // US-44 (round 7): vibe tags + daily mood, optional, bound to this trip only.
                      Text('สไตล์การเดินทางของคุณวันนี้ (ไม่บังคับ)', style: theme.textTheme.titleMedium),
                      const SizedBox(height: AppSpacing.md),
                      VibeTagChipPicker(
                        role: form.mode == TravelMode.car ? form.role : null,
                        selected: form.vibeTags,
                        onToggle: (tag) {
                          final issue = validateVibeTagSelection(
                            current: form.vibeTags,
                            candidate: tag,
                            role: form.mode == TravelMode.car ? form.role : null,
                          );
                          if (issue == VibeTagIssue.maxReached) {
                            ScaffoldMessenger.of(context)
                                .showSnackBar(const SnackBar(content: Text('เลือกได้สูงสุด 3 แท็ก เอาแท็กเดิมออกก่อนนะ')));
                            return;
                          }
                          ctrl.toggleVibeTag(tag);
                        },
                      ),
                      const SizedBox(height: AppSpacing.md),
                      MoodTextField(value: form.moodText, onChanged: ctrl.setMood),
                      const SizedBox(height: AppSpacing.xl),
                      // US-45: Women-Only (institution filter dropped entirely this round).
                      SafetyFilterSwitchGroup(value: form.womenOnly, onChanged: ctrl.setWomenOnly),
                    ],
                  ),
                ),
              ],
            ),
          ),
          FlowBottomBar(label: 'ถัดไป', onPressed: _canNext(form) ? _next : null),
        ],
      ),
    ));
  }
}

/// Collapsed by default; auto-opens if the user already set something inside it (e.g. navigating
/// back from step 3), so a filled-in choice is never hidden from view.
class _OptionalSettingsPanel extends StatefulWidget {
  const _OptionalSettingsPanel({required this.hasContent, required this.child});
  final bool hasContent;
  final Widget child;

  @override
  State<_OptionalSettingsPanel> createState() => _OptionalSettingsPanelState();
}

class _OptionalSettingsPanelState extends State<_OptionalSettingsPanel> {
  late bool _expanded = widget.hasContent;

  @override
  Widget build(BuildContext context) {
    final c = context.tone;
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: AppShape.cardRadius,
        boxShadow: c.cardShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: const Key('optional-settings-panel'),
          initiallyExpanded: _expanded,
          onExpansionChanged: (v) => setState(() => _expanded = v),
          title: Text('ตั้งค่าเพิ่มเติม (ไม่บังคับ)', style: Theme.of(context).textTheme.titleMedium),
          childrenPadding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
          children: [widget.child],
        ),
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({required this.mode, required this.selected, required this.onTap});
  final TravelMode mode;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: mode.label,
      child: InkWell(
        customBorder: AppShape.card(),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 96),
          decoration: BoxDecoration(
            color: selected ? context.tone.primaryTint : context.tone.surface,
            border: selected ? Border.all(color: context.tone.primaryInk, width: 2) : null,
            borderRadius: AppShape.cardRadius,
            boxShadow: selected ? null : context.tone.cardShadow,
          ),
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(mode.icon, size: 28, color: selected ? context.tone.primaryInk : context.tone.text),
              const SizedBox(height: AppSpacing.xs),
              Text(mode.label, textAlign: TextAlign.center),
              if (mode == TravelMode.car)
                Text(
                  R.carSublabel,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: context.tone.textSecondary),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
