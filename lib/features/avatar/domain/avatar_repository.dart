import 'dart:typed_data';

import '../../../core/error/result.dart';

/// Where an avatar image comes from: a short-lived signed URL (real backend) or bytes (demo / tests).
class AvatarSource {
  const AvatarSource.url(String this.url) : bytes = null;
  const AvatarSource.bytes(Uint8List this.bytes) : url = null;
  final String? url;
  final Uint8List? bytes;
}

/// Reasons offered in S-41. Mapped onto the `report_reason` enum of the server.
enum AvatarReportReason {
  notThisPerson('ไม่ใช่รูปของบุคคลนี้', 'fake_profile'),
  inappropriate('มีเนื้อหาไม่เหมาะสม', 'harassment'),
  otherPeople('มีบุคคลอื่นในรูป', 'other'),
  other('อื่น ๆ', 'other');

  const AvatarReportReason(this.label, this.db);
  final String label;
  final String db;
}

abstract class AvatarRepository {
  /// My own photo (null = none). Signed URL, valid for a couple of minutes.
  Future<Result<AvatarSource?>> mine();

  /// The partner's photo for [matchId]; null whenever the server says I may not see it
  /// (not matched / window over / blocked / reported by me): the UI then shows initials.
  Future<Result<AvatarSource?>> partner(String matchId);

  /// Uploads [jpeg] to `avatars/<uid>/avatar.jpg` (overwrite) and points the profile at it.
  Future<Result<void>> setMine(Uint8List jpeg);

  /// Clears the profile photo; the server queues the file for deletion.
  Future<Result<void>> removeMine();

  Future<Result<void>> report(String matchId, AvatarReportReason reason);
}
