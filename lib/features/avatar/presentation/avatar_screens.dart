import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/error/app_failure.dart';
import '../../../core/error/failure_messages.dart';
import '../../../core/l10n/strings_r5.dart';
import '../../../core/providers.dart';
import '../../../core/router/redirect.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/tone.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/role_badge.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../profile/presentation/profile_providers.dart';
import '../../trip/domain/trip.dart' show TripRole;
import '../domain/avatar_processing.dart';
import '../domain/avatar_repository.dart';
import 'avatar_providers.dart';
import 'user_avatar.dart';

String _errText(AvatarErrorKind k) => switch (k) {
      AvatarErrorKind.notImage => R5.photoErrNotImage,
      AvatarErrorKind.tooLarge => R5.photoErrTooLarge,
      AvatarErrorKind.tooSmall => R5.photoErrTooSmall,
      AvatarErrorKind.unsupported => R5.photoErrUnsupported,
    };

String uploadFailureText(AppFailure f) => switch (f.code) {
      FailureCode.networkOffline || FailureCode.networkTimeout => R5.photoErrOffline,
      FailureCode.uploadTooLarge || FailureCode.uploadType || 'GWM_AVATAR_INVALID' => R5.photoErrServer,
      'GWM_RATE_LIMITED' => failureMessage(f),
      _ => R5.photoErrUpload,
    };

const _noticeKey = 'avatar_notice_seen';

/// E-4 as a sheet. [mustAck] = the first time: a single "continue" button; later it is just info.
Future<bool> showPhotoPrivacySheet(BuildContext context, {bool mustAck = false}) async {
  final ok = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    isDismissible: !mustAck,
    enableDrag: !mustAck,
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          key: const Key('photo-privacy-sheet'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(R5.photoPrivacyTitle, style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: AppSpacing.md),
            const _Point(Icons.handshake_outlined, R5.photoPrivacyWho),
            const _Point(Icons.schedule, R5.photoPrivacyWhen),
            const _Point(Icons.visibility_off_outlined, R5.photoPrivacyNotWho),
            const _Point(Icons.delete_outline, R5.photoPrivacyControl),
            const SizedBox(height: AppSpacing.lg),
            AppButton(label: R5.photoPrivacyAck, onPressed: () => Navigator.of(ctx).pop(true)),
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop(false);
                context.push(Routes.policy);
              },
              child: const Text('นโยบายความเป็นส่วนตัว'),
            ),
          ],
        ),
      ),
    ),
  );
  return ok == true;
}

class _Point extends StatelessWidget {
  const _Point(this.icon, this.text);
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 22),
          const SizedBox(width: AppSpacing.md),
          Expanded(child: Text(text)),
        ]),
      );
}

/// S-35 /me/photo.
class AvatarScreen extends ConsumerStatefulWidget {
  const AvatarScreen({super.key});

  @override
  ConsumerState<AvatarScreen> createState() => _AvatarScreenState();
}

class _AvatarScreenState extends ConsumerState<AvatarScreen> {
  bool _busy = false;
  String _status = '';
  int _token = 0; // bumped by "cancel" so a late result is ignored
  String? _error;
  bool _permDenied = false;

  bool get _noticeSeen => ref.read(sharedPrefsProvider).getBool(_noticeKey) ?? false;

  Future<void> _start() async {
    if (_busy) return;
    if (!_noticeSeen) {
      final ok = await showPhotoPrivacySheet(context, mustAck: true);
      if (!ok || !mounted) return;
      await ref.read(sharedPrefsProvider).setBool(_noticeKey, true);
    }
    if (!mounted) return;
    final source = await showModalBottomSheet<PhotoSource?>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => _SourceSheet(denied: _permDenied),
    );
    if (source == null || !mounted) return;
    await _pickAndUpload(source);
  }

  Future<void> _pickAndUpload(PhotoSource source) async {
    final token = ++_token;
    setState(() {
      _busy = true;
      _error = null;
      _status = R5.photoPreparing;
    });
    final messenger = ScaffoldMessenger.of(context);
    final picked = await ref.read(avatarPickerProvider).pick(source);
    if (!mounted || token != _token) return;
    if (picked.denied) {
      setState(() {
        _busy = false;
        _permDenied = true;
        _error = R5.photoPermDenied;
      });
      return;
    }
    final bytes = picked.bytes;
    if (bytes == null) {
      setState(() => _busy = false);
      return;
    }
    ProcessedAvatar processed;
    try {
      processed = await ref.read(avatarProcessorProvider)(bytes);
    } on AvatarException catch (e) {
      if (mounted && token == _token) {
        setState(() {
        _busy = false;
        _error = _errText(e.kind);
      });
      }
      return;
    } catch (_) {
      if (mounted && token == _token) {
        setState(() {
        _busy = false;
        _error = R5.photoErrNotImage;
      });
      }
      return;
    }
    if (!mounted || token != _token) return;
    setState(() => _status = R5.photoUploading);
    final res = await ref.read(avatarRepositoryProvider).setMine(processed.bytes);
    if (token != _token) return; // cancelled: the previous photo stays in the UI
    _refresh();
    if (!mounted) return;
    res.when(
      ok: (_) {
        setState(() => _busy = false);
        messenger.showSnackBar(const SnackBar(content: Text(R5.photoSaved)));
      },
      err: (f) => setState(() {
        _busy = false;
        _error = uploadFailureText(f);
      }),
    );
  }

  void _refresh() {
    ref.read(avatarServiceProvider).evictMine();
    ref.invalidate(myAvatarProvider);
    ref.invalidate(currentProfileProvider);
  }

  Future<void> _remove() async {
    if (_busy) return;
    final ok = await showConfirmDialog(
      context,
      title: R5.photoRemoveTitle,
      body: R5.photoRemoveBody,
      safeLabel: R5.photoCancel,
      confirmLabel: R5.photoRemove,
    );
    if (!ok || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
      _status = '';
    });
    final messenger = ScaffoldMessenger.of(context);
    final res = await ref.read(avatarRepositoryProvider).removeMine();
    if (!mounted) return;
    res.when(
      ok: (_) {
        _refresh();
        setState(() => _busy = false);
        messenger.showSnackBar(const SnackBar(content: Text(R5.photoRemoved)));
      },
      err: (f) => setState(() {
        _busy = false;
        _error = f.code == FailureCode.networkOffline ? R5.photoErrOffline : R5.photoErrDelete;
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = ref.watch(currentProfileProvider).valueOrNull?.displayName ??
        ref.watch(authUserProvider).valueOrNull?.displayName ??
        '';
    final mine = ref.watch(myAvatarProvider);
    final hasPhoto = mine.valueOrNull != null;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text(R5.photoTitle)),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.pageH),
        children: [
          const SizedBox(height: AppSpacing.md),
          Center(child: UserAvatar.mine(name: name, size: 160)),
          const SizedBox(height: AppSpacing.md),
          if (!hasPhoto && !mine.isLoading)
            Text(R5.photoEmptyHint, textAlign: TextAlign.center, style: theme.textTheme.bodyMedium?.copyWith(color: context.tone.textSecondary)),
          const SizedBox(height: AppSpacing.lg),
          if (_busy) ...[
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: AppSpacing.md),
              Text(_status),
            ]),
            const SizedBox(height: AppSpacing.sm),
            AppButton(
              key: const Key('photo-cancel'),
              label: R5.photoCancel,
              variant: AppButtonVariant.text,
              onPressed: () => setState(() {
                _token++;
                _busy = false;
              }),
            ),
          ] else ...[
            AppButton(
              key: const Key('photo-pick'),
              label: hasPhoto ? R5.photoChange : R5.photoPick,
              icon: Icons.photo_camera_outlined,
              onPressed: _start,
            ),
            if (hasPhoto) ...[
              const SizedBox(height: AppSpacing.sm),
              AppButton(
                key: const Key('photo-remove'),
                label: R5.photoRemove,
                variant: AppButtonVariant.danger,
                icon: Icons.delete_outline,
                onPressed: _remove,
              ),
            ],
          ],
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.md),
              child: Text(_error!, key: const Key('photo-error'), style: TextStyle(color: context.tone.dangerInk), textAlign: TextAlign.center),
            ),
          const SizedBox(height: AppSpacing.xl),
          Row(children: [
            const Icon(Icons.lock_outline, size: 20),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: Text(R5.photoPrivacyShort, style: theme.textTheme.bodyMedium)),
          ]),
          TextButton(
            key: const Key('photo-privacy-more'),
            onPressed: () => showPhotoPrivacySheet(context),
            child: const Text(R5.photoPrivacyMore),
          ),
        ],
      ),
    );
  }
}

/// E-5. Camera only on phones; on web a single "choose a file" row (browser dialog).
class _SourceSheet extends StatelessWidget {
  const _SourceSheet({required this.denied});
  final bool denied;

  @override
  Widget build(BuildContext context) {
    Widget row(IconData icon, String label, PhotoSource s, Key key) => ListTile(
          key: key,
          minTileHeight: 56,
          leading: Icon(icon),
          title: Text(label),
          onTap: () => Navigator.of(context).pop(s),
        );
    return SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (!kIsWeb) row(Icons.photo_camera_outlined, R5.photoSourceCamera, PhotoSource.camera, const Key('src-camera')),
        row(
          kIsWeb ? Icons.upload_file_outlined : Icons.photo_library_outlined,
          kIsWeb ? R5.photoSourceFile : R5.photoSourceGallery,
          PhotoSource.gallery,
          const Key('src-gallery'),
        ),
        if (denied)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.sm),
            child: Text(R5.photoPermDenied),
          ),
        ListTile(
          minTileHeight: 56,
          leading: const Icon(Icons.text_fields),
          title: const Text(R5.photoKeepInitials),
          onTap: () => Navigator.of(context).pop(),
        ),
      ]),
    );
  }
}

/// E-3: partner photo viewer sheet with "report this photo".
Future<void> showPartnerPhotoSheet(
  BuildContext context, {
  required String matchId,
  required String partnerId,
  required String name,
  TripRole? role,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => Consumer(builder: (ctx, ref, _) {
      final src = ref.watch(partnerAvatarProvider(matchId));
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            UserAvatar.partner(name: name, matchId: matchId, size: 200),
            const SizedBox(height: AppSpacing.md),
            Text(name, style: Theme.of(ctx).textTheme.titleLarge),
            if (role != null) ...[const SizedBox(height: AppSpacing.sm), RoleBadge(role)],
            const SizedBox(height: AppSpacing.md),
            if (src.valueOrNull != null)
              TextButton.icon(
                key: const Key('photo-report'),
                icon: const Icon(Icons.flag_outlined),
                label: const Text(R5.photoReportCta),
                style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                onPressed: () {
                  Navigator.of(ctx).pop();
                  context.push(Routes.reportPhoto(partnerId, matchId: matchId, name: name));
                },
              ),
          ]),
        ),
      );
    }),
  );
}

/// S-41 /report/photo/:userId?match=..&name=..
class ReportPhotoScreen extends ConsumerStatefulWidget {
  const ReportPhotoScreen({super.key, required this.userId, this.matchId, this.name});
  final String userId;
  final String? matchId;
  final String? name;

  @override
  ConsumerState<ReportPhotoScreen> createState() => _ReportPhotoState();
}

class _ReportPhotoState extends ConsumerState<ReportPhotoScreen> {
  AvatarReportReason? _reason;
  bool _busy = false;
  String? _error;

  Future<void> _submit() async {
    final reason = _reason;
    final match = widget.matchId;
    if (reason == null || match == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    final res = await ref.read(avatarRepositoryProvider).report(match, reason);
    if (!mounted) return;
    res.when(
      ok: (_) {
        // The photo is hidden from me right away (server also hides it): drop the cache and re-read.
        ref.read(avatarServiceProvider).evictMatch(match);
        ref.invalidate(partnerAvatarProvider(match));
        messenger.showSnackBar(const SnackBar(content: Text(R5.photoReportDone)));
        context.pop();
      },
      err: (f) => setState(() {
        _busy = false;
        _error = f.code == 'GWM_REPORT_INVALID' ? R5.photoReportAlready : failureMessage(f);
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(widget.name == null ? R5.photoReportTitle : '${R5.photoReportTitle}: ${widget.name}')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.pageH),
        children: [
          RadioGroup<AvatarReportReason>(
            groupValue: _reason,
            onChanged: (v) => setState(() => _reason = v),
            child: Column(children: [
              for (final r in AvatarReportReason.values)
                RadioListTile<AvatarReportReason>(
                  value: r,
                  title: Text(r.label),
                  contentPadding: EdgeInsets.zero,
                ),
            ]),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(R5.photoReportAnon, style: theme.textTheme.bodyMedium?.copyWith(color: context.tone.textSecondary)),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Text(_error!, style: TextStyle(color: context.tone.dangerInk)),
            ),
          const SizedBox(height: AppSpacing.lg),
          AppButton(
            key: const Key('photo-report-submit'),
            label: R5.photoReportSubmit,
            loading: _busy,
            onPressed: _reason == null ? null : _submit,
          ),
        ],
      ),
    );
  }
}
