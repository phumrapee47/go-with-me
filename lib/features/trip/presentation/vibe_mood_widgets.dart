import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/theme/tone.dart';
import '../domain/trip.dart';
import '../domain/vibe_mood.dart';

/// G-5 VibeTagChipPicker (design-spec-round7 G.3.2). Up to 3 tags from the
/// role allow-list; the 4th attempted tap is rejected with a short inline
/// message, never a hard error.
class VibeTagChipPicker extends StatelessWidget {
  const VibeTagChipPicker({super.key, required this.role, required this.selected, required this.onToggle});

  final TripRole? role;
  final List<String> selected;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    final all = VibeTagCatalog.forRole(role);
    if (all.isEmpty) return const SizedBox.shrink();
    final atMax = selected.length >= VibeTagCatalog.maxTags;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          liveRegion: true,
          child: Text('เลือกแล้ว ${selected.length}/${VibeTagCatalog.maxTags}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: context.tone.textSecondary)),
        ),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            for (final tag in all)
              Semantics(
                button: true,
                selected: selected.contains(tag),
                label: !selected.contains(tag) && atMax ? '$tag: เลือกได้สูงสุด 3 แท็ก' : tag,
                child: FilterChip(
                  key: Key('vibe-chip-$tag'),
                  label: Text(tag),
                  selected: selected.contains(tag),
                  onSelected: (!selected.contains(tag) && atMax) ? null : (_) => onToggle(tag),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// G-6 MoodTextField (design-spec-round7 G.3.2).
class MoodTextField extends StatefulWidget {
  const MoodTextField({super.key, required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;

  @override
  State<MoodTextField> createState() => _MoodTextFieldState();
}

class _MoodTextFieldState extends State<MoodTextField> {
  late final _controller = TextEditingController(text: widget.value);

  @override
  void didUpdateWidget(covariant MoodTextField old) {
    super.didUpdateWidget(old);
    if (widget.value != _controller.text) {
      _controller.value = TextEditingValue(text: widget.value, selection: TextSelection.collapsed(offset: widget.value.length));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final value = widget.value;
    final issue = VibeMoodValidator.validateMood(value);
    final over = value.length > moodMaxLength;
    final near = !over && value.length >= 30;
    return TextField(
      key: const Key('mood-text-field'),
      controller: _controller,
      onChanged: widget.onChanged,
      decoration: InputDecoration(
        labelText: 'ข้อความ mood ประจำทริปนี้ (ไม่บังคับ)',
        hintText: 'เช่น วันนี้ขอฟังเพลงเงียบ ๆ นะ',
        errorText: issue == null
            ? null
            : (issue == MoodIssue.overLimit ? 'สั้นลงอีกนิดนะ (สูงสุด 35 ตัวอักษร)' : 'อย่าใส่เบอร์โทรหรือลิงก์ในข้อความนี้นะ'),
        errorMaxLines: 2,
        suffixText: '${value.length}/$moodMaxLength',
        suffixStyle: TextStyle(color: over ? context.tone.dangerInk : (near ? context.tone.warningInk : context.tone.textSecondary)),
      ),
    );
  }
}

/// G-7 TripVibeSummaryRow (compact, read-only — CommuteCard/candidate & match detail).
class TripVibeSummaryRow extends StatelessWidget {
  const TripVibeSummaryRow({super.key, required this.vibeTags, required this.moodText, this.compact = true});
  final List<String> vibeTags;
  final String? moodText;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (vibeTags.isEmpty && (moodText == null || moodText!.isEmpty)) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (moodText != null && moodText!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: Text(
              '"${moodText!}"',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic, color: context.tone.textSecondary),
            ),
          ),
        if (vibeTags.isNotEmpty)
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              for (final tag in vibeTags)
                Chip(
                  key: Key('vibe-summary-$tag'),
                  label: Text(tag, style: Theme.of(context).textTheme.bodySmall),
                  visualDensity: compact ? VisualDensity.compact : VisualDensity.standard,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
            ],
          ),
      ],
    );
  }
}
