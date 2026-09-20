import 'package:flutter/material.dart';

import '../../core/l10n/gen/app_localizations.dart';

class PlaceholderTab extends StatelessWidget {
  const PlaceholderTab({super.key, required this.title});
  final String title;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: Center(child: Text(AppLocalizations.of(context).comingSoon)),
      );
}
