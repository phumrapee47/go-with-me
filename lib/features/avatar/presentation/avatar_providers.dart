import 'dart:typed_data';

import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

import '../../auth/presentation/auth_providers.dart';
import '../../matching/domain/match_models.dart';
import '../../matching/presentation/matching_providers.dart';
import '../data/supabase_avatar_repository.dart';
import '../domain/avatar_processing.dart';
import '../domain/avatar_repository.dart';
import '../domain/avatar_service.dart';

final avatarRepositoryProvider = Provider<AvatarRepository>(
  (ref) => SupabaseAvatarRepository(Supabase.instance.client),
);

/// Cache in front of the repository; rebuilt (dropped) when the signed-in user changes.
final avatarServiceProvider = Provider<AvatarService>((ref) {
  ref.watch(authUserProvider.select((a) => a.valueOrNull?.id));
  return AvatarService(ref.watch(avatarRepositoryProvider));
});

/// My own photo (null = initials).
final myAvatarProvider = FutureProvider.autoDispose<AvatarSource?>((ref) {
  return ref.watch(avatarServiceProvider).mine();
});

/// True when the accepted match may show the partner's photo at all (client side pre-check; the server
/// decides for real). Search results, pending / declined / cancelled-before-boarding never do (E-1).
bool matchMayShowPhoto(MatchSummary? m) =>
    m != null && (m.status == MatchStatus.accepted || (m.status == MatchStatus.cancelled && m.boarded));

/// The partner's photo for one match, or null (initials). Re-evaluated whenever the match state changes.
final partnerAvatarProvider = FutureProvider.autoDispose.family<AvatarSource?, String>((ref, matchId) async {
  final service = ref.watch(avatarServiceProvider);
  // Rebuild when this match changes state (accepted -> ended, boarded...).
  ref.watch(inboxProvider.select((a) {
    final l = a.valueOrNull;
    if (l == null) return null;
    for (final m in l) {
      if (m.id == matchId) return '${m.status.db}|${m.boarded}';
    }
    return 'none';
  }));
  final inbox = ref.read(inboxProvider).valueOrNull;
  if (inbox != null) {
    final m = inbox.where((x) => x.id == matchId).firstOrNull;
    if (!matchMayShowPhoto(m)) {
      service.evictMatch(matchId);
      return null;
    }
  }
  return service.partner(matchId);
});

/// Resize/encode step (runs in an isolate); replaceable in tests.
final avatarProcessorProvider = Provider<Future<ProcessedAvatar> Function(Uint8List)>((_) => processAvatar);

// ---- picking ---------------------------------------------------------------------------------

enum PhotoSource { camera, gallery }

class PickOutcome {
  const PickOutcome.picked(Uint8List this.bytes) : denied = false;
  const PickOutcome.cancelled() : bytes = null, denied = false;
  const PickOutcome.denied() : bytes = null, denied = true;
  final Uint8List? bytes;
  final bool denied;
}

abstract class AvatarPicker {
  Future<PickOutcome> pick(PhotoSource source);
}

/// image_picker: gallery / camera on phones, the browser file dialog on web. The system asks for the
/// permission itself when the row is tapped (nothing is requested up front).
class ImagePickerAvatarPicker implements AvatarPicker {
  const ImagePickerAvatarPicker();

  @override
  Future<PickOutcome> pick(PhotoSource source) async {
    try {
      final f = await ImagePicker().pickImage(
        source: source == PhotoSource.camera ? ImageSource.camera : ImageSource.gallery,
        maxWidth: 2048,
        maxHeight: 2048,
        requestFullMetadata: false,
      );
      if (f == null) return const PickOutcome.cancelled();
      return PickOutcome.picked(await f.readAsBytes());
    } on PlatformException catch (e) {
      if (e.code.contains('denied') || e.code.contains('access')) return const PickOutcome.denied();
      return const PickOutcome.cancelled();
    } catch (_) {
      return const PickOutcome.cancelled();
    }
  }
}

final avatarPickerProvider = Provider<AvatarPicker>((_) => const ImagePickerAvatarPicker());
