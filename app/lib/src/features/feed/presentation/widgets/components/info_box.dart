import 'package:flutter/material.dart';

import '../app_colors.dart';

class InfoBox extends StatelessWidget {
  const InfoBox({
    required this.title,
    required this.body,
    required this.color,
    this.accent,
    super.key,
  });

  final String title;
  final String body;
  final Color color;

  /// Optional accent for the title (e.g. the engagement-state color) —
  /// defaults to the neutral muted-text color when omitted.
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: accent ?? AppColors.mutedText,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.ink,
                  height: 1.25,
                ),
          ),
        ],
      ),
    );
  }
}
