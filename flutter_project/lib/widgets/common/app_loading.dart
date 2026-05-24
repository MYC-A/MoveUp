import 'package:flutter/material.dart';

import 'package:flutter_application_1/theme/app_spacing.dart';

class AppLoading extends StatelessWidget {
  final String? label;

  const AppLoading({super.key, this.label});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          if (label != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(label!, style: textTheme.bodyMedium),
          ],
        ],
      ),
    );
  }
}
