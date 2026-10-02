import '../../../core/l10n/strings_roles.dart';

enum CompanionKind { none, riderSide, driverSide }

/// The other person of a car match as far as an outgoing share/SOS text is
/// concerned (R3-1, PM Q-decisions). The backend is the enforcement point for
/// backend links and the SOS snapshot; for plain text built on the phone this
/// object carries ONLY what may leave the app:
///  * Rider's text: the Driver's display name (always) and the plate (only
///    when the Driver switched consent on). Never model or colour.
///  * Driver's text: own plate (own data, no switch) and the Rider's name.
class ShareCompanion {
  const ShareCompanion.none()
      : kind = CompanionKind.none,
        partnerName = null,
        plate = null,
        plateAllowed = false,
        statusKnown = true;

  const ShareCompanion.rider({
    required String this.partnerName,
    this.plate,
    this.plateAllowed = false,
    this.statusKnown = true,
  }) : kind = CompanionKind.riderSide;

  const ShareCompanion.driver({required String this.partnerName, this.plate})
      : kind = CompanionKind.driverSide,
        plateAllowed = true,
        statusKnown = true;

  final CompanionKind kind;
  final String? partnerName;

  /// Plate to put in the text, or null. For the Rider side it is only ever
  /// non-null while [plateAllowed] is true.
  final String? plate;

  /// Rider side: the Driver's consent switch as last read from the server.
  final bool plateAllowed;

  /// Rider side: false when the consent status could not be loaded (the text
  /// then carries the Driver's name only and nothing waits for it).
  final bool statusKnown;

  bool get hasPlate => plate != null && plate!.isNotEmpty;

  /// True when the two companions would produce different text.
  bool sameTextAs(ShareCompanion o) =>
      kind == o.kind && partnerName == o.partnerName && (hasPlate ? plate : null) == (o.hasPlate ? o.plate : null);
}

/// Lines appended to a share/SOS text for [c] (empty when there is no match).
List<String> companionLines(ShareCompanion c) => switch (c.kind) {
      CompanionKind.none => const [],
      CompanionKind.riderSide => [
          '${R.textDriverLine}: ${c.partnerName}',
          if (c.plateAllowed && c.hasPlate) '${R.textPlateLine}: ${c.plate}',
        ],
      CompanionKind.driverSide => [
          if (c.hasPlate) '${R.textPlateLine}: ${c.plate}',
          '${R.textRiderLine}: ${c.partnerName}',
        ],
    };

/// One-line preview under "what will be shared" (null = nothing to say).
String? sharePreviewLine(ShareCompanion c) => switch (c.kind) {
      CompanionKind.none => null,
      CompanionKind.riderSide =>
        c.plateAllowed && c.hasPlate ? R.sharePreviewRiderWithPlate : R.sharePreviewRiderNoPlate,
      CompanionKind.driverSide => R.sharePreviewDriver,
    };

/// Preview under the SOS confirm button. If the status could not be loaded it
/// falls back to "name only" and never blocks (F-R11.4).
String? sosPreviewLine(ShareCompanion c) => switch (c.kind) {
      CompanionKind.none => null,
      CompanionKind.riderSide => !c.statusKnown
          ? R.sosPreviewRiderFallback
          : (c.plateAllowed && c.hasPlate ? R.sosPreviewRiderWithPlate : R.sosPreviewRiderNoPlate),
      CompanionKind.driverSide => R.sosPreviewDriver,
    };
