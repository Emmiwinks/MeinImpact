import 'package:flutter/material.dart';

import '../app_colors.dart';

class ProgressLine extends StatelessWidget {
  const ProgressLine({required this.value, super.key});

  final double value;

  @override
  Widget build(BuildContext context) {
    final progress = value.clamp(0, 1).toDouble();
    return ClipRRect(
      borderRadius: BorderRadius.circular(99),
      child: Container(
        height: 4,
        color: AppColors.subtleBorder,
        child: FractionallySizedBox(
          alignment: AlignmentDirectional.centerStart,
          widthFactor: progress,
          child: Container(color: AppColors.green),
        ),
      ),
    );
  }
}
