import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/tokens.dart';

/// C-2. Label always sits above the field (no placeholder-as-label).
class AppTextField extends StatefulWidget {
  const AppTextField({
    super.key,
    required this.label,
    this.controller,
    this.validator,
    this.helper,
    this.errorText,
    this.obscure = false,
    this.enabled = true,
    this.keyboardType,
    this.textInputAction,
    this.autofillHints,
    this.onChanged,
    this.onFieldSubmitted,
    this.focusNode,
    this.maxLength,
    this.autovalidateMode = AutovalidateMode.onUserInteraction,
  });

  final String label;
  final TextEditingController? controller;
  final FormFieldValidator<String>? validator;
  final String? helper;

  /// Server-side error to show under the field (e.g. duplicate email).
  final String? errorText;
  final bool obscure;
  final bool enabled;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onFieldSubmitted;
  final FocusNode? focusNode;
  final int? maxLength;
  final AutovalidateMode autovalidateMode;

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  late bool _hidden = widget.obscure;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.label, style: theme.textTheme.labelLarge),
        const SizedBox(height: AppSpacing.xs + 2),
        TextFormField(
          controller: widget.controller,
          focusNode: widget.focusNode,
          enabled: widget.enabled,
          obscureText: _hidden,
          keyboardType: widget.keyboardType,
          textInputAction: widget.textInputAction,
          autofillHints: widget.autofillHints,
          autovalidateMode: widget.autovalidateMode,
          validator: widget.validator,
          onChanged: widget.onChanged,
          onFieldSubmitted: widget.onFieldSubmitted,
          maxLength: widget.maxLength,
          inputFormatters: widget.maxLength == null
              ? null
              : [LengthLimitingTextInputFormatter(widget.maxLength)],
          style: theme.textTheme.bodyLarge,
          decoration: InputDecoration(
            helperText: widget.helper,
            helperMaxLines: 2,
            errorText: widget.errorText,
            counterText: '',
            suffixIcon: widget.obscure
                ? IconButton(
                    tooltip: _hidden ? 'แสดงรหัสผ่าน' : 'ซ่อนรหัสผ่าน',
                    icon: Icon(_hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                    onPressed: () => setState(() => _hidden = !_hidden),
                  )
                : null,
          ),
        ),
      ],
    );
  }
}
