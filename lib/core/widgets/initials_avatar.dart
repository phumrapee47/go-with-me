import 'package:flutter/material.dart';

import '../theme/tone.dart';

/// First letter shown in an [AvatarInitial] ('?' when the name is blank).
/// Latin letters are upper-cased; Thai/other scripts are used as-is (first grapheme).
String avatarInitial(String name) {
  final t = name.trim();
  if (t.isEmpty) return '?';
  return t.characters.first.toUpperCase();
}

/// C-27 central avatar (MVP 0.1: initials only; profile photos are P1/T3.27).
/// Used by profile (Me tab), match lists/detail and chat.
class AvatarInitial extends StatelessWidget {
  const AvatarInitial({super.key, required this.name, this.radius = 24});
  final String name;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final style = radius >= 36 ? Theme.of(context).textTheme.titleLarge : Theme.of(context).textTheme.titleMedium;
    return ExcludeSemantics(
      child: CircleAvatar(
        radius: radius,
        backgroundColor: context.tone.infoBg,
        child: Text(avatarInitial(name), style: style),
      ),
    );
  }
}
