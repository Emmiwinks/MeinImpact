import 'package:flutter/material.dart';

import '../app_colors.dart';

class SignalDots extends StatelessWidget {
  const SignalDots({required this.score, super.key});

  final int score;

  @override
  Widget build(BuildContext context) {
    final activeDots = (score / 25).ceil().clamp(1, 4).toInt();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var index = 0; index < 4; index++) ...[
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color:
                  index < activeDots ? AppColors.green : AppColors.subtleBorder,
              shape: BoxShape.circle,
            ),
          ),
          if (index != 3) const SizedBox(width: 3),
        ],
      ],
    );
  }
}
