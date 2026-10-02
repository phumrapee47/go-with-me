import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/strings_r6_cd.dart';
import '../../../core/router/redirect.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/tone.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/state_view.dart';
import '../../geo/presentation/current_location.dart';
import '../../geo/presentation/pick_point_screen.dart';
import '../../geo/presentation/place_search_field.dart';
import '../../trip/domain/trip.dart' show Place;
import '../../trip/domain/trip_form.dart';
import '../domain/preset.dart';
import 'preset_providers.dart';

/// P-4 summary: two rows with edit / remove. Everything here is saved on this device only.
class PresetSummaryScreen extends ConsumerWidget {
  const PresetSummaryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(presetsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text(R6C.placesTitle)),
      body: data.when(
        loading: () => const StateView.loading(),
        error: (_, _) => const StateView.error(title: R6C.saveFailed),
        data: (d) => ListView(
          padding: const EdgeInsets.all(AppSpacing.pageH),
          children: [
            _Row(kind: PresetKind.home, title: R6C.homeRow, preset: d.home),
            const SizedBox(height: AppSpacing.md),
            _Row(kind: PresetKind.start, title: R6C.startRow, preset: d.start),
            const SizedBox(height: AppSpacing.lg),
            Row(children: [
              const Icon(Icons.lock_outline, size: 18),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: Text(R6C.localOnlyCaption, key: const Key('places-local-caption'), style: TextStyle(color: context.tone.textSecondary))),
            ]),
            const SizedBox(height: AppSpacing.xl),
            AppButton(
              key: const Key('places-done'),
              label: R6C.done,
              onPressed: () => context.canPop() ? context.pop() : context.go(Routes.home),
            ),
          ],
        ),
      ),
    );
  }
}

class _Row extends ConsumerWidget {
  const _Row({required this.kind, required this.title, required this.preset});
  final PresetKind kind;
  final String title;
  final PlacePreset? preset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final p = preset;
    return AppCard(
      key: Key('places-row-${kind.db}'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(kind == PresetKind.home ? Icons.home_outlined : Icons.work_outline),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(p == null ? '$title: ${R6C.notSet}' : '$title: ${p.name}', style: theme.textTheme.titleMedium),
          ),
        ]),
        const SizedBox(height: AppSpacing.sm),
        Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.xs, children: [
          if (p == null)
            AppButton(
              key: Key('places-set-${kind.db}'),
              label: kind == PresetKind.home ? R6C.setHome : R6C.setStart,
              expand: false,
              onPressed: () => context.push(Routes.mePlace(kind.db)),
            )
          else ...[
            AppButton(
              key: Key('places-edit-${kind.db}'),
              label: R6C.edit,
              expand: false,
              variant: AppButtonVariant.secondary,
              icon: Icons.edit_outlined,
              onPressed: () => context.push(Routes.mePlace(kind.db)),
            ),
            AppButton(
              key: Key('places-remove-${kind.db}'),
              label: R6C.remove,
              expand: false,
              variant: AppButtonVariant.text,
              icon: Icons.delete_outline,
              onPressed: () async {
                final ok = await showConfirmDialog(
                  context,
                  title: R6C.removeTitle(p.name),
                  body: R6C.removeBody,
                  safeLabel: R6C.noticeCancel,
                  confirmLabel: R6C.remove,
                );
                if (!ok || !context.mounted) return;
                await ref.read(presetsProvider.notifier).remove(kind);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(R6C.removed)));
                }
              },
            ),
          ],
        ]),
      ]),
    );
  }
}

/// P-2 / P-3: set or edit the Home / regular start. The privacy notice is shown once, before the first save.
class PresetEditScreen extends ConsumerStatefulWidget {
  const PresetEditScreen({super.key, required this.kind});
  final PresetKind kind;

  @override
  ConsumerState<PresetEditScreen> createState() => _PresetEditState();
}

class _PresetEditState extends ConsumerState<PresetEditScreen> {
  late final TextEditingController _name;
  Place? _place;
  StartType _type = StartType.work;
  String? _error;
  bool _saving = false;
  bool _nameTouched = false;
  bool _loaded = false;

  bool get _isHome => widget.kind == PresetKind.home;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: _isHome ? R6C.homeName : _typeLabel(StartType.work));
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  static String _typeLabel(StartType t) => switch (t) {
        StartType.work => R6C.typeWork,
        StartType.campus => R6C.typeCampus,
        StartType.other => R6C.typeOther,
      };

  void _loadExisting(PresetData d) {
    if (_loaded) return;
    _loaded = true;
    final p = _isHome ? d.home : d.start;
    if (p == null) return;
    _place = p.toPlace();
    _name.text = p.name;
    _nameTouched = true;
    _type = p.startType ?? StartType.work;
  }

  void _setPlace(Place p) => setState(() {
        _place = p;
        _error = null;
      });

  Future<void> _pickOnMap() async {
    final place = await Navigator.of(context).push<Place>(
      MaterialPageRoute(
        builder: (_) => PickPointScreen(
          title: _isHome ? R6C.editHomeTitle : R6C.editStartTitle,
          initial: _place?.point,
        ),
      ),
    );
    if (place != null && mounted) _setPlace(place);
  }

  Future<void> _useCurrent() async {
    final p = await obtainCurrentLocation(context, ref);
    if (p == null || !mounted) return;
    final label = await labelFor(ref, p);
    if (mounted) _setPlace(Place(point: p, label: label));
  }

  String? _validate(PresetData d) {
    final name = _name.text.trim();
    if (_place == null) return R6C.pickPlaceFirst;
    if (name.isEmpty) return R6C.nameEmpty;
    if (name.characters.length > presetNameMaxLen) return R6C.nameTooLong;
    // The regular start may not be (almost) the same place as Home: same rule as the wizard (>= 200 m).
    final other = _isHome ? d.start : d.home;
    if (other != null) {
      final home = _isHome ? _place! : other.toPlace();
      final start = _isHome ? other.toPlace() : _place!;
      if (TripFormValidator.validatePlaces(start, home) != null) return R6C.sameAsHome;
    }
    return null;
  }

  Future<bool> _confirmNotice() async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            key: const Key('places-notice'),
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                const Icon(Icons.lock_outline),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: Text(R6C.noticeTitle, style: Theme.of(ctx).textTheme.titleLarge)),
              ]),
              const SizedBox(height: AppSpacing.md),
              const Text(R6C.noticeBody),
              const SizedBox(height: AppSpacing.md),
              Text(R6C.noticeImportant, style: Theme.of(ctx).textTheme.titleSmall),
              const SizedBox(height: AppSpacing.xl),
              AppButton(key: const Key('places-notice-ok'), label: R6C.noticeOk, onPressed: () => Navigator.of(ctx).pop(true)),
              AppButton(
                key: const Key('places-notice-cancel'),
                label: R6C.noticeCancel,
                variant: AppButtonVariant.text,
                onPressed: () => Navigator.of(ctx).pop(false),
              ),
            ],
          ),
        ),
      ),
    );
    return ok == true;
  }

  Future<void> _save() async {
    if (_saving) return;
    final d = ref.read(presetsProvider).valueOrNull ?? PresetData.empty;
    final err = _validate(d);
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    if (!d.noticeSeen) {
      if (!await _confirmNotice() || !mounted) return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final ok = await ref.read(presetsProvider.notifier).save(
          widget.kind,
          PlacePreset(
            name: _name.text.trim(),
            label: _place!.label,
            point: _place!.point,
            startType: _isHome ? null : _type,
          ),
        );
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _saving = false;
        _error = R6C.saveFailed;
      });
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(R6C.saved)));
    // Setup flow: Home first, then the regular start, then the summary.
    final after = ref.read(presetsProvider).valueOrNull ?? PresetData.empty;
    if (_isHome && after.start == null) {
      context.pushReplacement(Routes.mePlace(PresetKind.start.db));
    } else if (context.canPop()) {
      context.pop();
    } else {
      context.go(Routes.mePlaces);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(presetsProvider);
    final d = async.valueOrNull;
    if (d != null) _loadExisting(d);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(_isHome ? R6C.editHomeTitle : R6C.editStartTitle)),
      body: d == null
          ? const StateView.loading()
          : ListView(
              padding: const EdgeInsets.all(AppSpacing.pageH),
              children: [
                if (!_isHome) ...[
                  Text(R6C.typeGroup, style: theme.textTheme.titleSmall),
                  const SizedBox(height: AppSpacing.xs),
                  Semantics(
                    container: true,
                    label: R6C.typeGroup,
                    child: Wrap(spacing: AppSpacing.sm, children: [
                      for (final t in StartType.values)
                        ChoiceChip(
                          key: Key('start-type-${t.db}'),
                          label: Text(_typeLabel(t)),
                          selected: _type == t,
                          onSelected: (_) => setState(() {
                            _type = t;
                            // Keep a name the user typed; otherwise follow the type.
                            if (!_nameTouched) _name.text = _typeLabel(t);
                          }),
                        ),
                    ]),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                ],
                TextField(
                  key: const Key('place-name'),
                  controller: _name,
                  maxLength: presetNameMaxLen,
                  onChanged: (_) => _nameTouched = true,
                  decoration: const InputDecoration(labelText: R6C.nameLabel, hintText: R6C.nameHint),
                ),
                const SizedBox(height: AppSpacing.md),
                PlaceSearchField(
                  key: ValueKey('preset-place-${widget.kind.db}'),
                  label: _isHome ? R6C.placeLabelHome : R6C.placeLabelStart,
                  place: _place,
                  onSelected: _setPlace,
                  onCleared: () => setState(() => _place = null),
                  onPickOnMap: _pickOnMap,
                  onUseCurrent: _useCurrent,
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.md),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(_error!, key: const Key('place-error'), style: TextStyle(color: context.tone.dangerInk)),
                    ),
                  ),
                const SizedBox(height: AppSpacing.md),
                Row(children: [
                  const Icon(Icons.lock_outline, size: 18),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: Text(R6C.localOnlyCaption, style: TextStyle(color: context.tone.textSecondary))),
                ]),
                const SizedBox(height: AppSpacing.xl),
                AppButton(
                  key: const Key('place-save'),
                  label: _isHome && d.start == null ? R6C.next : R6C.save,
                  loading: _saving,
                  onPressed: _place == null ? null : _save,
                ),
              ],
            ),
    );
  }
}
