/// US-47 (round 7 Stage C): "สติกเกอร์ขอบคุณ" — a FIXED allow-list reusing the existing quick-reply
/// pattern (US-8/US-24) and sent through the normal chat channel (`chat_messages`, `kind='user'`, no
/// new `kind`/schema needed — see docs/design-roles.md #15.2). No free-text entry.
abstract final class ThankYouStickerPresets {
  static const messages = <String>[
    'ขอบคุณมากนะ!',
    'ขับปลอดภัยครับ',
    'เพลงเพราะมาก',
    'เจอกันใหม่นะ',
  ];
}
