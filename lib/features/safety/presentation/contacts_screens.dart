import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/error/app_failure.dart';
import '../../../core/error/failure_messages.dart';
import '../../../core/error/result.dart';
import '../../../core/l10n/strings_p4.dart';
import '../../../core/router/redirect.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/tone.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/state_view.dart';
import '../domain/safety_models.dart';
import 'safety_providers.dart';

/// S-26: emergency contacts list (max 3, warn before deleting the last).
class ContactsScreen extends ConsumerWidget {
  const ContactsScreen({super.key});

  Future<void> _delete(BuildContext context, WidgetRef ref, EmergencyContact c, int count) async {
    final last = ContactRules.deleteNeedsLastWarning(count);
    final body = P.contactDeleteBody.replaceFirst('%s', c.name) + (last ? '\n\n${P.contactDeleteLastBody}' : '');
    final ok = await showConfirmDialog(
      context,
      title: P.contactDeleteTitle,
      body: body,
      safeLabel: P.contactDeleteKeep,
      confirmLabel: P.contactDelete,
    );
    if (!ok || !context.mounted) return;
    final res = await ref.read(contactsProvider.notifier).delete(c.id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res.when(ok: (_) => P.contactDeleted, err: failureMessage))));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contacts = ref.watch(contactsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text(P.contactsTitle)),
      body: contacts.when(
        loading: () => const StateView.loading(),
        error: (e, _) => StateView.failure(
          e is AppFailure ? e : const AppFailure(FailureCode.unknown),
          onRetry: () => ref.invalidate(contactsProvider),
        ),
        data: (list) {
          final canAdd = ContactRules.canAdd(list.length);
          return ListView(
            padding: const EdgeInsets.all(AppSpacing.pageH),
            children: [
              Text(
                P.contactsCount.replaceFirst('%s', '${list.length}'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.md),
              if (list.isEmpty)
                const StateView.empty(
                  icon: Icons.contact_phone_outlined,
                  title: P.contactsEmpty,
                  message: P.contactsEmptyBody,
                ),
              for (final c in list)
                Card(
                  child: ListTile(
                    minTileHeight: AppSpacing.minTap,
                    title: Text(c.name),
                    subtitle: Text(c.maskedPhone),
                    trailing: Wrap(children: [
                      IconButton(
                        tooltip: '${P.contactEdit} ${c.name}',
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () => context.push(Routes.contactEdit(id: c.id)),
                      ),
                      IconButton(
                        tooltip: '${P.contactDelete} ${c.name}',
                        icon: Icon(Icons.delete_outline, color: context.tone.dangerInk),
                        onPressed: () => _delete(context, ref, c, list.length),
                      ),
                    ]),
                  ),
                ),
              const SizedBox(height: AppSpacing.md),
              AppButton(
                label: P.contactsAdd,
                icon: Icons.person_add_alt,
                onPressed: canAdd ? () => context.push(Routes.contactEdit()) : null,
              ),
              if (!canAdd)
                const Padding(
                  padding: EdgeInsets.only(top: AppSpacing.sm),
                  child: AppCard(tone: AppCardTone.warning, child: Text(P.contactsMax)),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// S-26 form: add or edit (id in the query string).
class ContactEditScreen extends ConsumerStatefulWidget {
  const ContactEditScreen({super.key, this.contactId});
  final String? contactId;

  @override
  ConsumerState<ContactEditScreen> createState() => _ContactEditState();
}

class _ContactEditState extends ConsumerState<ContactEditScreen> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  String? _nameErr;
  String? _phoneErr;
  bool _saving = false;
  bool _seeded = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final nameOk = ContactRules.isValidName(_name.text);
    final phoneOk = ContactRules.isValidPhone(_phone.text);
    setState(() {
      _nameErr = nameOk ? null : P.errContactName;
      _phoneErr = phoneOk ? null : P.errContactPhone;
    });
    if (!nameOk || !phoneOk || _saving) return;
    setState(() => _saving = true);
    final ctrl = ref.read(contactsProvider.notifier);
    final Result<EmergencyContact> res = widget.contactId == null
        ? await ctrl.add(_name.text, _phone.text)
        : await ctrl.edit(widget.contactId!, _name.text, _phone.text);
    if (!mounted) return;
    setState(() => _saving = false);
    switch (res) {
      case Ok():
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(P.contactSaved)));
        context.pop();
      case Err(:final failure):
        if (failure.code == FailureCode.duplicate || failure.code == 'GWM_ALREADY_EXISTS') {
          setState(() => _phoneErr = P.errContactDuplicate);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(failureMessage(failure))));
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.contactId;
    if (id != null && !_seeded) {
      final existing = ref.watch(contactsProvider).valueOrNull?.where((c) => c.id == id).firstOrNull;
      if (existing != null) {
        _name.text = existing.name;
        _phone.text = existing.phone;
        _seeded = true;
      }
    }
    return Scaffold(
      appBar: AppBar(title: Text(id == null ? P.contactNew : P.contactEdit)),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.pageH),
        children: [
          AppTextField(
            label: P.contactName,
            controller: _name,
            errorText: _nameErr,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: AppSpacing.lg),
          AppTextField(
            label: P.contactPhone,
            controller: _phone,
            errorText: _phoneErr,
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: AppSpacing.xl),
          AppButton(label: P.contactSave, loading: _saving, onPressed: _save),
        ],
      ),
    );
  }
}
