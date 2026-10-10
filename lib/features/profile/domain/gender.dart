/// US-45 (round 7, design-roles §14 / requirements-round7-ba.md): self-declared,
/// optional, self-view-only gender used ONLY to gate the Women-Only trip
/// switch. Never shown on a public profile, never sent to a partner (server
/// enforces this — `profiles.gender` is not in any SELECT grant a partner can
/// reach; `get_my_gender()` is self-view only).
enum Gender {
  female('female', 'หญิง'),
  male('male', 'ชาย'),
  // DB check profiles_gender_chk allows only female|male|other (0012), so "ไม่ระบุ" is stored as 'other'.
  unspecified('other', 'ไม่ระบุ');

  const Gender(this.db, this.label);
  final String db;
  final String label;

  static Gender? fromDb(Object? v) {
    for (final g in values) {
      if (g.db == v) return g;
    }
    return null;
  }

  /// Only "female" unlocks anything (Women-Only) this round — per the AC, no
  /// other value unlocks any extra eligibility.
  bool get unlocksWomenOnly => this == Gender.female;
}
