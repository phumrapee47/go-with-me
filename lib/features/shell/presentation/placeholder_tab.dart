import 'package:flutter/material.dart';

import '../../../core/l10n/strings.dart';
import '../../../core/widgets/state_view.dart';

/// Empty-state placeholder used by tabs until their feature ships.
class PlaceholderTab extends StatelessWidget {
  const PlaceholderTab({
    super.key,
    required this.title,
    required this.emptyTitle,
    required this.emptyBody,
    required this.icon,
  });

  final String title;
  final String emptyTitle;
  final String emptyBody;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: StateView.empty(
        icon: icon,
        title: emptyTitle,
        message: '$emptyBody\n\n${S.comingSoon}',
      ),
    );
  }
}
