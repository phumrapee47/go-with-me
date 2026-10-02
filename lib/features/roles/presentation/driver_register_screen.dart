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
import '../../vehicle/domain/vehicle.dart';
import '../../vehicle/presentation/vehicle_providers.dart';
import '../domain/role_state.dart';
import 'role_providers.dart';
import 'role_strip.dart';

/// In-app paths the registration flow may return to (design-spec D.9 allow-list).
String? registerReturnTo(String? raw) {
  final safe = safeReturnTo(raw);
  if (safe == null) return null;
  final path = Uri.tryParse(safe)?.path;
  return const {'/me', '/trip/new/options', '/home'}.contains(path) ? safe : null;
}

/// D-6..D-9 `/me/driver/register`: vehicle (3 fields) + licence self-declaration in one page,
/// sent as ONE atomic call. Success offers (never forces) the switch to Driver mode.
class DriverRegisterScreen extends ConsumerStatefulWidget {
  const DriverRegisterScreen({super.key, this.returnTo});
  final String? returnTo;

  @override
  ConsumerState<DriverRegisterScreen> createState() => _DriverRegisterScreenState();
}

class _DriverRegisterScreenState extends ConsumerState<DriverRegisterScreen> {
  final _plate = TextEditingController();
  final _model = TextEditingController();
  final _color = TextEditingController();
  bool _seeded = false;
  bool _prefilled = false;
  bool _declared = false;
  bool _submitting = false;
  bool _success = false;
  bool _switching = false;
  bool _showErrors = false;
  String? _error;
  Map<VehicleField, VehicleIssue> _issues = const {};

  @override
  void dispose() {
    _plate.dispose();
    _model.dispose();
    _color.dispose();
    super.dispose();
  }

  DriverRegistrationInput get _input =>
      DriverRegistrationInput(plate: _plate.text, model: _model.text, colour: _color.text, declared: _declared);

  bool get _dirty => _plate.text.isNotEmpty || _model.text.isNotEmpty || _color.text.isNotEmpty || _declared;

  String? _fieldError(VehicleField f, String required) => switch (_issues[f]) {
        VehicleIssue.required => required,
        VehicleIssue.tooLong => R.errTooLong,
        null => null,
      };

  void _seed(Vehicle? v) {
    if (_seeded) return;
    _seeded = true;
    if (v != null) {
      _plate.text = v.plate;
      _model.text = v.model;
      _color.text = v.color;
      _prefilled = true;
    }
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final check = DriverRegistrationValidator.validate(_input);
    setState(() {
      _issues = check.fields;
      _showErrors = true;
      _error = null;
    });
    if (!check.isValid) return;
    setState(() => _submitting = true);
    final res = await ref.read(roleControllerProvider.notifier).register(_input);
    if (!mounted) return;
    final f = res.failureOrNull;
    setState(() {
      _submitting = false;
      if (f == null) {
        _success = true;
      } else {
        _error = _errorText(f);
      }
    });
  }

  String _errorText(AppFailure f) {
    switch (f.code) {
      case FailureCode.networkOffline:
      case FailureCode.networkTimeout:
        return D.errNetwork;
      case 'GWM_DECLARATION_REQUIRED':
      case 'GWM_DECLARATION_VERSION_STALE':
      case 'GWM_VEHICLE_INVALID':
      case 'GWM_RATE_LIMITED':
        return failureMessage(f);
      default:
        return D.errServer;
    }
  }

  /// Back to where the user came from (the trip draft lives in a provider, so nothing is lost).
  void _leave() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(registerReturnTo(widget.returnTo) ?? Routes.me);
    }
  }

  Future<void> _onBack() async {
    if (_submitting) return; // the close button is off while waiting (no half-sent state)
    if (!_dirty || _success) {
      _leave();
      return;
    }
    final leave = await showConfirmDialog(
      context,
      title: D.discardTitle,
      body: D.discardBody,
      safeLabel: D.discardStay,
      confirmLabel: D.discardLeave,
    );
    if (leave && mounted) _leave();
  }

  Future<void> _switchThenLeave() async {
    setState(() => _switching = true);
    final out = await performRoleSwitch(context, ref, ActiveRole.driver);
    if (!mounted) return;
    setState(() => _switching = false);
    if (out != RoleSwitchOutcome.switched) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text(D.successSwitchFailed)));
    }
    _leave();
  }

  @override
  Widget build(BuildContext context) {
    final registered = ref.watch(driverRegisteredProvider);
    final vehicle = ref.watch(myVehicleProvider);

    // Already registered (and not just now): the edit page is /me/vehicle. While our own request is in
    // flight the controller already reports "registered": that must not bounce us away from the success view.
    if (registered == true && !_success && !_submitting) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.pushReplacement(Routes.vehicle);
      });
      return const Scaffold(body: StateView.loading());
    }
    if (_success) return _successView(context);

    if (vehicle.isLoading && !vehicle.hasValue) {
      return Scaffold(appBar: AppBar(title: const Text(D.regTitle)), body: const StateView.loading());
    }
    _seed(vehicle.valueOrNull);

    final check = DriverRegistrationValidator.validate(_input);
    final tone = context.tone;
    final theme = Theme.of(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBack();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text(D.regTitle),
          leading: IconButton(
            key: const Key('register-close'),
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            icon: const Icon(Icons.arrow_back),
            onPressed: _submitting ? null : _onBack,
          ),
        ),
        body: Column(children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.pageH),
              children: [
                const _DriverNoticeCard(),
                const SizedBox(height: AppSpacing.lg),
                if (_prefilled) ...[
                  AppCard(
                    tone: AppCardTone.info,
                    child: Row(children: [
                      Icon(Icons.info_outline, color: tone.accentInk),
                      const SizedBox(width: AppSpacing.sm),
                      const Expanded(child: Text(D.prefillBanner, key: Key('prefill-banner'))),
                    ]),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                ],
                Text(D.sectionVehicle, style: theme.textTheme.titleMedium),
                const SizedBox(height: AppSpacing.md),
                AppTextField(
                  label: R.plate,
                  controller: _plate,
                  helper: R.plateHint,
                  enabled: !_submitting,
                  errorText: _fieldError(VehicleField.plate, R.errPlateRequired),
                  textInputAction: TextInputAction.next,
                  onChanged: (_) => setState(() => _issues = const {}),
                ),
                const SizedBox(height: AppSpacing.md),
                AppTextField(
                  label: R.model,
                  controller: _model,
                  helper: R.modelHint,
                  enabled: !_submitting,
                  errorText: _fieldError(VehicleField.model, R.errModelRequired),
                  textInputAction: TextInputAction.next,
                  onChanged: (_) => setState(() => _issues = const {}),
                ),
                const SizedBox(height: AppSpacing.md),
                AppTextField(
                  label: R.color,
                  controller: _color,
                  enabled: !_submitting,
                  errorText: _fieldError(VehicleField.color, R.errColorRequired),
                  textInputAction: TextInputAction.done,
                  onChanged: (_) => setState(() => _issues = const {}),
                ),
                const SizedBox(height: AppSpacing.sm),
                Wrap(spacing: AppSpacing.sm, children: [
                  for (final c in R.colorChips)
                    ChoiceChip(
                      label: Text(c),
                      selected: _color.text.trim() == c,
                      onSelected: _submitting ? null : (_) => setState(() => _color.text = c),
                    ),
                ]),
                const SizedBox(height: AppSpacing.lg),
                _LicenceDeclaration(
                  value: _declared,
                  enabled: !_submitting,
                  showError: _showErrors && !_declared,
                  onChanged: (v) => setState(() => _declared = v),
                ),
                const SizedBox(height: AppSpacing.md),
                Text(D.consentHint, style: theme.textTheme.bodyMedium?.copyWith(color: tone.textSecondary)),
                if (_error != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  AppCard(tone: AppCardTone.error, child: Text(_error!, key: const Key('register-error'))),
                ],
                const SizedBox(height: AppSpacing.lg),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(AppSpacing.pageH, AppSpacing.sm, AppSpacing.pageH, AppSpacing.sm),
              decoration: BoxDecoration(color: tone.surface, border: Border(top: BorderSide(color: tone.border))),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (!check.isValid && !_submitting)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                    child: Text(D.ctaDisabledReason, key: const Key('register-disabled-reason'), style: theme.textTheme.bodyMedium?.copyWith(color: tone.textSecondary)),
                  ),
                AppButton(
                  key: const Key('register-submit'),
                  label: _submitting ? D.submitting : D.regCta,
                  loading: false,
                  icon: _submitting ? Icons.hourglass_top : null,
                  onPressed: (check.isValid && !_submitting) ? _submit : null,
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  /// D-9: registered. Offers the switch; never switches by itself.
  Widget _successView(BuildContext context) {
    final theme = Theme.of(context);
    final fromTrip = registerReturnTo(widget.returnTo)?.startsWith('/trip/new') ?? false;
    return Scaffold(
      appBar: AppBar(title: const Text(D.regTitle), automaticallyImplyLeading: false),
      body: SafeArea(
        child: ListView(
          key: const Key('register-success'),
          padding: const EdgeInsets.all(AppSpacing.pageH),
          children: [
            const SizedBox(height: AppSpacing.xl),
            Center(child: Icon(Icons.check_circle, size: 72, color: context.tone.successInk)),
            const SizedBox(height: AppSpacing.lg),
            Text(D.successTitle, style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.sm),
            const Text(D.successBody, textAlign: TextAlign.center),
            if (fromTrip) ...[
              const SizedBox(height: AppSpacing.xs),
              const Text(D.successReturnTrip, textAlign: TextAlign.center),
            ],
            const SizedBox(height: AppSpacing.xl),
            AppButton(
              key: const Key('success-switch'),
              label: D.successSwitch,
              loading: _switching,
              onPressed: _switching ? null : _switchThenLeave,
            ),
            const SizedBox(height: AppSpacing.md),
            AppButton(
              key: const Key('success-later'),
              label: D.successLater,
              variant: AppButtonVariant.secondary,
              onPressed: _switching ? null : _leave,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(D.consentHint, style: theme.textTheme.bodyMedium?.copyWith(color: context.tone.textSecondary), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

/// D-8: says plainly that this is self-declared and not checked, 1 companion, no money.
class _DriverNoticeCard extends StatelessWidget {
  const _DriverNoticeCard();

  @override
  Widget build(BuildContext context) {
    Widget row(IconData icon, String t) => Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, size: 20, color: context.tone.accentInk),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: Text(t)),
          ]),
        );
    return AppCard(
      key: const Key('driver-notice'),
      tone: AppCardTone.info,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        row(Icons.info_outline, D.notice1),
        row(Icons.person_outline, D.notice2),
        row(Icons.money_off, D.notice3),
      ]),
    );
  }
}

/// D-7: never pre-ticked; whole row taps; note is always visible.
class _LicenceDeclaration extends StatelessWidget {
  const _LicenceDeclaration({required this.value, required this.enabled, required this.showError, required this.onChanged});
  final bool value;
  final bool enabled;
  final bool showError;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final tone = context.tone;
    final theme = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.control),
          border: showError ? Border.all(color: tone.dangerInk, width: 2) : null,
        ),
        child: CheckboxListTile(
          key: const Key('declaration-checkbox'),
          contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
          controlAffinity: ListTileControlAffinity.leading,
          value: value,
          onChanged: enabled ? (v) => onChanged(v ?? false) : null,
          title: const Text(D.decl),
        ),
      ),
      if (showError)
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.xs),
          child: Row(children: [
            Icon(Icons.error_outline, size: 18, color: tone.dangerInk),
            const SizedBox(width: AppSpacing.xs),
            Expanded(child: Text(D.errDeclRequired, key: const Key('declaration-error'), style: TextStyle(color: tone.dangerInk))),
          ]),
        ),
      Padding(
        padding: const EdgeInsets.only(top: AppSpacing.xs, left: AppSpacing.xs),
        child: Text(D.declNote, style: theme.textTheme.bodyMedium?.copyWith(color: tone.textSecondary)),
      ),
    ]);
  }
}
