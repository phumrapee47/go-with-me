import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/strings_r5.dart';
import '../../../core/theme/tone.dart';
import '../../../core/widgets/initials_avatar.dart';
import '../domain/avatar_repository.dart';
import 'avatar_providers.dart';

/// E-1: photo or initials. Always circular; never shows a photo unless the caller passes [matchId] of an
/// accepted match (or [mine]); search results / pending requests simply use [AvatarInitial].
/// Any problem (loading > 3 s, error, no access, offline, reported) ends in the same quiet initials.
class UserAvatar extends ConsumerWidget {
  const UserAvatar.partner({super.key, required this.name, required String this.matchId, this.size = 40, this.onTap})
      : mine = false;
  const UserAvatar.mine({super.key, required this.name, this.size = 96, this.onTap})
      : mine = true,
        matchId = null;

  final String name;
  final String? matchId;
  final bool mine;
  final double size;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<AvatarSource?> src =
        mine ? ref.watch(myAvatarProvider) : ref.watch(partnerAvatarProvider(matchId!));
    final source = src.valueOrNull;
    final initials = AvatarInitial(name: name, radius: size / 2);
    Widget child = source == null
        ? Semantics(label: R5.photoInitialLabel(name), excludeSemantics: true, child: initials)
        : Semantics(
            label: R5.photoAvatarLabel(name),
            image: true,
            excludeSemantics: true,
            child: _PhotoCircle(key: ValueKey(source.url ?? source.bytes.hashCode), source: source, size: size, fallback: initials),
          );
    if (onTap != null) {
      // >= 48 dp hit area around small avatars.
      child = InkResponse(
        onTap: onTap,
        radius: (size < 48 ? 48 : size) / 2,
        child: SizedBox(width: size < 48 ? 48 : size, height: size < 48 ? 48 : size, child: Center(child: child)),
      );
    }
    return child;
  }
}

class _PhotoCircle extends StatefulWidget {
  const _PhotoCircle({super.key, required this.source, required this.size, required this.fallback});
  final AvatarSource source;
  final double size;
  final Widget fallback;

  @override
  State<_PhotoCircle> createState() => _PhotoCircleState();
}

class _PhotoCircleState extends State<_PhotoCircle> {
  bool _giveUp = false;
  bool _loaded = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Loading never lasts: after 3 s we fall back to initials without any message.
    _timer = Timer(const Duration(seconds: 3), () {
      if (mounted && !_loaded) setState(() => _giveUp = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_giveUp) return widget.fallback;
    final s = widget.size;
    final skeleton = Container(width: s, height: s, decoration: BoxDecoration(shape: BoxShape.circle, color: context.tone.infoBg));
    final bytes = widget.source.bytes;
    final url = widget.source.url;
    Widget image;
    if (bytes != null) {
      _loaded = true;
      image = Image.memory(bytes, width: s, height: s, fit: BoxFit.cover, gaplessPlayback: true, errorBuilder: (_, _, _) => widget.fallback);
    } else {
      image = Image.network(
        url!,
        width: s,
        height: s,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        loadingBuilder: (_, child, progress) {
          if (progress == null) {
            _loaded = true;
            return child;
          }
          return skeleton;
        },
        errorBuilder: (_, _, _) => widget.fallback,
      );
    }
    return Container(
      width: s,
      height: s,
      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: context.tone.surface, width: s >= 56 ? 2 : 1)),
      child: ClipOval(child: image),
    );
  }
}
