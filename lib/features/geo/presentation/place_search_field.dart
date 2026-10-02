import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/strings_trip.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/tone.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../trip/domain/trip.dart';
import 'geo_providers.dart';
import 'place_search_controller.dart';

/// C-8: search field + result list + shortcuts (current location, map pin).
class PlaceSearchField extends ConsumerStatefulWidget {
  const PlaceSearchField({
    super.key,
    required this.label,
    required this.place,
    required this.onSelected,
    required this.onCleared,
    required this.onPickOnMap,
    this.onUseCurrent,
    this.autofocus = false,
  });

  final String label;
  final Place? place;
  final ValueChanged<Place> onSelected;
  final VoidCallback onCleared;
  final VoidCallback onPickOnMap;
  final VoidCallback? onUseCurrent;
  final bool autofocus;

  @override
  ConsumerState<PlaceSearchField> createState() => _PlaceSearchFieldState();
}

class _PlaceSearchFieldState extends ConsumerState<PlaceSearchField> {
  late final PlaceSearchController _search =
      PlaceSearchController(ref.read(geocodingServiceProvider))..addListener(_onSearch);
  late final TextEditingController _text = TextEditingController(text: widget.place?.label ?? '');

  void _onSearch() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(PlaceSearchField old) {
    super.didUpdateWidget(old);
    final label = widget.place?.label;
    // Place set from outside (map pin / current location): mirror in the text.
    if (label != null && label != old.place?.label && _text.text != label) {
      _text.text = label;
      _search.clear();
    }
    if (widget.place == null && old.place != null && _text.text == old.place!.label) {
      _text.clear();
    }
  }

  @override
  void dispose() {
    _search
      ..removeListener(_onSearch)
      ..dispose();
    _text.dispose();
    super.dispose();
  }

  void _changed(String v) {
    if (widget.place != null && v != widget.place!.label) widget.onCleared();
    _search.onQueryChanged(v);
  }

  void _pick(Place p) {
    _text.text = p.label;
    _search.clear();
    FocusManager.instance.primaryFocus?.unfocus();
    widget.onSelected(p);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppTextField(
          label: widget.label,
          controller: _text,
          helper: T.searchHint,
          textInputAction: TextInputAction.search,
          onChanged: _changed,
          onFieldSubmitted: _search.searchNow,
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          children: [
            if (widget.onUseCurrent != null)
              AppButton(
                label: T.useCurrent,
                icon: Icons.my_location,
                expand: false,
                variant: AppButtonVariant.tonal,
                onPressed: widget.onUseCurrent,
              ),
            AppButton(
              label: T.pickOnMap,
              icon: Icons.push_pin_outlined,
              expand: false,
              variant: AppButtonVariant.secondary,
              onPressed: widget.onPickOnMap,
            ),
          ],
        ),
        _panel(theme),
      ],
    );
  }

  Widget _panel(ThemeData theme) {
    switch (_search.status) {
      case PlaceSearchStatus.idle:
        return const SizedBox.shrink();
      case PlaceSearchStatus.typing:
      case PlaceSearchStatus.loading:
        return const Padding(
          padding: EdgeInsets.all(AppSpacing.md),
          child: Row(children: [
            SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: AppSpacing.md),
            Text(T.searching),
          ]),
        );
      case PlaceSearchStatus.empty:
        return _note(T.noPlaceFound);
      case PlaceSearchStatus.rateLimited:
        return _note(T.searchRateLimited);
      case PlaceSearchStatus.unavailable:
        return _note(T.searchUnavailable);
      case PlaceSearchStatus.results:
        return Column(
          children: [
            for (final (index, s) in _search.results.indexed)
              ListTile(
                key: ValueKey(
                    'place-$index-${s.label}-${s.point.latitude}-${s.point.longitude}'),
                minTileHeight: AppSpacing.minTap,
                leading: const Icon(Icons.place_outlined),
                title: Text(s.label, maxLines: 2, overflow: TextOverflow.ellipsis),
                onTap: () => _pick(Place(point: s.point, label: s.label)),
              ),
          ],
        );
    }
  }

  Widget _note(String text) => Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Text(text, style: TextStyle(color: context.tone.textSecondary)),
      );
}
