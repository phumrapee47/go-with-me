import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/error/app_failure.dart';
import '../../../core/error/failure_messages.dart';
import '../../../core/l10n/strings_dual.dart';
import '../../../core/l10n/strings_roles.dart';
import '../../../core/router/redirect.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/tone.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/state_view.dart';
import '../../matching/domain/match_models.dart';
import '../../matching/presentation/matching_providers.dart';
import '../../roles/presentation/role_cards.dart';
import '../../roles/presentation/role_providers.dart';
import '../domain/vehicle.dart';
import 'vehicle_providers.dart';
import 'vehicle_widgets.dart';

/// S-33 (`/me/vehicle`): fill / edit / delete the vehicle and the plate-sharing
/// switch. [returnTo] (in-app path only) brings the user back to the create-trip
/// step; the trip draft lives in a provider so nothing is lost meanwhile.
class VehicleScreen extends ConsumerStatefulWidget {
  const VehicleScreen({super.key, this.returnTo});
  final String? returnTo;

  @override
  ConsumerState<VehicleScreen> createState() => _VehicleScreenState();
}

class _VehicleScreenState extends ConsumerState<VehicleScreen> {
  final _plate = TextEditingController();
  final _model = TextEditingController();
  final _color = TextEditingController();
  Map<VehicleField, VehicleIssue> _issues = const {};
  bool _seeded = false;
  bool _saving = false;
  bool _consentBusy = false;
  bool _showWithdrawNotice = false;
  String? _consentError;
  String? _saveError;

  /// Choice made before any vehicle exists; applied after the first save (F-R2.4).
  bool _pendingConsent = false;

  @override
  void dispose() {
    _plate.dispose();
    _model.dispose();
    _color.dispose();
    super.dispose();
  }

  void _seed(Vehicle? v) {
    if (_seeded) return;
    _seeded = true;
    if (v != null) {
      _plate.text = v.plate;
      _model.text = v.model;
      _color.text = v.color;
    }
  }

  bool _dirty(Vehicle? v) {
    if (v == null) {
      return _plate.text.isNotEmpty || _model.text.isNotEmpty || _color.text.isNotEmpty;
    }
    return _plate.text != v.plate || _model.text != v.model || _color.text != v.color;
  }

  String? _issueText(VehicleField f, String required) => switch (_issues[f]) {
        VehicleIssue.required => required,
        VehicleIssue.tooLong => R.errTooLong,
        null => null,
      };

  Future<void> _save(Vehicle? existing) async {
    if (_saving) return;
    final input = VehicleInput(plate: _plate.text, model: _model.text, color: _color.text);
    final issues = VehicleValidator.validate(input);
    setState(() {
      _issues = issues;
      _saveError = null;
    });
    if (issues.isNotEmpty) return;

    final inbox = ref.read(inboxProvider).valueOrNull ?? const <MatchSummary>[];
    final hasMatch = inbox.any((m) => m.status == MatchStatus.accepted && m.iAmDriver);
    if (existing != null && hasMatch) {
      final ok = await showConfirmDialog(
        context,
        title: R.editVehicle,
        body: R.editNotice,
        safeLabel: R.discardKeep,
        confirmLabel: R.save,
        destructive: false,
      );
      if (!ok || !mounted) return;
    }
    setState(() => _saving = true);
    final out = await ref.read(myVehicleProvider.notifier).save(
          VehicleInput(
            plate: VehicleValidator.normalise(_plate.text),
            model: VehicleValidator.normalise(_model.text),
            color: VehicleValidator.normalise(_color.text),
          ),
          wantConsent: existing == null ? _pendingConsent : null,
        );
    if (!mounted) return;
    setState(() => _saving = false);
    if (out.failure != null) {
      setState(() => _saveError = out.failure!.code == 'GWM_VEHICLE_INVALID' ? R.saveFailed : failureMessage(out.failure!));
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    if (out.consentFailed) {
      // The vehicle is saved; only the switch failed. Stay so it can be retried here.
      messenger.showSnackBar(const SnackBar(content: Text(R.sharePartialFailed)));
      setState(() => _pendingConsent = false);
      return;
    }
    messenger.showSnackBar(const SnackBar(content: Text(R.saved)));
    final back = safeReturnTo(widget.returnTo);
    if (back != null) {
      if (context.canPop()) {
        context.pop();
      } else {
        context.go(back);
      }
    } else if (context.canPop()) {
      context.pop();
    } else {
      context.go(Routes.me);
    }
  }

  Future<void> _toggleConsent(bool on, Vehicle? existing) async {
    if (existing == null) {
      // Nothing to send to the server yet: remember the choice.
      setState(() => _pendingConsent = on);
      return;
    }
    setState(() {
      _consentBusy = true;
      _consentError = null;
      _showWithdrawNotice = false;
    });
    final f = await ref.read(myVehicleProvider.notifier).setShareConsent(on);
    if (!mounted) return;
    setState(() {
      _consentBusy = false;
      if (f != null) {
        _consentError = R.shareFailed; // the switch stays where the server left it
      } else {
        _showWithdrawNotice = !on;
      }
    });
  }

  /// D-11 vehicle-delete-blocked-registered: the vehicle cannot go while the account is a registered driver.
  Future<void> _showRegisteredBlock() async {
    final messenger = ScaffoldMessenger.of(context);
    var goUnregister = false;
    await showBlockedReasonSheet(
      context,
      BlockedReason.vehicleRegistered,
      onPrimary: () => goUnregister = true,
    );
    if (!goUnregister || !mounted) return;
    final done = await showDialog<bool>(context: context, builder: (_) => const UnregisterDialog());
    if (done == true) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text(D.unregDone)));
    }
  }

  Future<void> _delete() async {
    // Registered drivers must unregister first; the server enforces it too (GWM_DRIVER_REGISTERED).
    if (ref.read(driverRegisteredProvider) == true) {
      await _showRegisteredBlock();
      return;
    }
    final ok = await showConfirmDialog(
      context,
      title: R.deleteTitle,
      body: R.deleteBody,
      safeLabel: R.deleteKeep,
      confirmLabel: R.delete,
    );
    if (!ok || !mounted) return;
    final f = await ref.read(myVehicleProvider.notifier).delete();
    if (!mounted) return;
    if (f != null) {
      if (f.code == 'GWM_DRIVER_REGISTERED') {
        await _showRegisteredBlock();
        return;
      }
      setState(() => _saveError = failureMessage(f));
      return;
    }
    _plate.clear();
    _model.clear();
    _color.clear();
    setState(() {
      _issues = const {};
      _pendingConsent = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(R.deleted)));
  }

  Widget _retainedView(BuildContext context, Vehicle v, bool locked) {
    return Scaffold(
      appBar: AppBar(title: const Text(R.vehicleTitle)),
      body: ListView(
        key: const Key('vehicle-retained'),
        padding: const EdgeInsets.all(AppSpacing.pageH),
        children: [
          VehicleInfoCard.ownerPreview(v),
          const SizedBox(height: AppSpacing.md),
          const Text(D.vehicleRetainedNote, key: Key('vehicle-retained-note')),
          const SizedBox(height: AppSpacing.lg),
          AppButton(
            key: const Key('vehicle-reregister'),
            label: D.vehicleReregisterCta,
            onPressed: () => context.pushReplacement(Routes.driverRegisterFor(returnTo: widget.returnTo)),
          ),
          if (_saveError != null) ...[
            const SizedBox(height: AppSpacing.md),
            AppCard(tone: AppCardTone.error, child: Text(_saveError!, key: const Key('vehicle-save-error'))),
          ],
          const SizedBox(height: AppSpacing.md),
          AppButton(
            key: const Key('vehicle-delete'),
            label: R.delete,
            variant: AppButtonVariant.text,
            onPressed: locked ? null : _delete,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vehicle = ref.watch(myVehicleProvider);
    final locked = ref.watch(vehicleDeleteLockedProvider);
    final theme = Theme.of(context);

    return vehicle.when(
      loading: () => Scaffold(appBar: AppBar(title: const Text(R.vehicleTitle)), body: const StateView.loading()),
      error: (e, _) => Scaffold(
        appBar: AppBar(title: const Text(R.vehicleTitle)),
        body: StateView.failure(
          e is AppFailure ? e : const AppFailure(FailureCode.unknown),
          onRetry: () => ref.invalidate(myVehicleProvider),
        ),
      ),
      data: (v) {
        final registered = ref.watch(driverRegisteredProvider);
        // First-time fill happens on the registration page (S-33 empty state replaced, round 4).
        if (v == null && registered == false) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) context.pushReplacement(Routes.driverRegisterFor(returnTo: widget.returnTo));
          });
          return Scaffold(appBar: AppBar(title: const Text(R.vehicleTitle)), body: const StateView.loading());
        }
        // Unregistered but the vehicle was kept (owner-only): view / delete / register again.
        if (v != null && registered == false) return _retainedView(context, v, locked);
        _seed(v);
        final consent = v?.shareConsent ?? _pendingConsent;
        return PopScope(
          canPop: !_dirty(v),
          onPopInvokedWithResult: (didPop, _) async {
            if (didPop) return;
            final discard = await showConfirmDialog(
              context,
              title: R.discardTitle,
              body: '',
              safeLabel: R.discardKeep,
              confirmLabel: R.discardConfirm,
            );
            if (discard && context.mounted) {
              // Reset the fields so the pop is allowed.
              setState(() {
                _plate.text = v?.plate ?? '';
                _model.text = v?.model ?? '';
                _color.text = v?.color ?? '';
              });
              if (context.canPop()) context.pop();
            }
          },
          child: Scaffold(
            appBar: AppBar(title: const Text(R.vehicleTitle)),
            body: ListView(
              padding: const EdgeInsets.all(AppSpacing.pageH),
              children: [
                if (v == null) ...[
                  Text(R.vehicleEmptyTitle, style: theme.textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.xs),
                  const Text(R.vehicleEmptyBody),
                  const SizedBox(height: AppSpacing.lg),
                ] else ...[
                  VehicleInfoCard.ownerPreview(v),
                  const SizedBox(height: AppSpacing.lg),
                ],
                AppTextField(
                  label: R.plate,
                  controller: _plate,
                  helper: R.plateHint,
                  errorText: _issueText(VehicleField.plate, R.errPlateRequired),
                  textInputAction: TextInputAction.next,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: AppSpacing.md),
                AppTextField(
                  label: R.model,
                  controller: _model,
                  helper: R.modelHint,
                  errorText: _issueText(VehicleField.model, R.errModelRequired),
                  textInputAction: TextInputAction.next,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: AppSpacing.md),
                AppTextField(
                  label: R.color,
                  controller: _color,
                  errorText: _issueText(VehicleField.color, R.errColorRequired),
                  textInputAction: TextInputAction.done,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: AppSpacing.sm),
                Wrap(spacing: AppSpacing.sm, children: [
                  for (final c in R.colorChips)
                    ChoiceChip(
                      label: Text(c),
                      selected: _color.text.trim() == c,
                      onSelected: (_) => setState(() => _color.text = c),
                    ),
                ]),
                const SizedBox(height: AppSpacing.lg),
                const _PrivacyNotice(),
                const SizedBox(height: AppSpacing.md),
                ShareConsentSwitch(
                  value: consent,
                  busy: _consentBusy,
                  showWithdrawNotice: _showWithdrawNotice,
                  errorText: _consentError,
                  onChanged: (on) => _toggleConsent(on, v),
                ),
                if (_saveError != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  AppCard(tone: AppCardTone.error, child: Text(_saveError!, key: const Key('vehicle-save-error'))),
                ],
                const SizedBox(height: AppSpacing.lg),
                AppButton(
                  key: const Key('vehicle-save'),
                  label: R.save,
                  loading: _saving,
                  onPressed: () => _save(v),
                ),
                if (v != null) ...[
                  const SizedBox(height: AppSpacing.lg),
                  if (locked)
                    const Text(R.deleteLocked, key: Key('vehicle-delete-locked')),
                  AppButton(
                    key: const Key('vehicle-delete'),
                    label: R.delete,
                    variant: AppButtonVariant.text,
                    onPressed: locked ? null : _delete,
                  ),
                ],
                const SizedBox(height: AppSpacing.xl),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Above the save button, never behind "see more" (C-33).
class _PrivacyNotice extends StatelessWidget {
  const _PrivacyNotice();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget bullet(String t) => Padding(
          padding: const EdgeInsets.only(top: AppSpacing.xs),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('• '),
            Expanded(child: Text(t)),
          ]),
        );
    return AppCard(
      tone: AppCardTone.info,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(R.privacyTitle, style: theme.textTheme.titleMedium),
        bullet(R.privacy1),
        bullet(R.privacy2),
        bullet(R.privacy3),
        const SizedBox(height: AppSpacing.sm),
        Text(R.unverified, style: theme.textTheme.bodyMedium?.copyWith(color: context.tone.textSecondary)),
      ]),
    );
  }
}
