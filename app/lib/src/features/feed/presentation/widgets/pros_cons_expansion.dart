import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Expandable pro/contra section — collapsed by default so it doesn't
/// dominate the card; the arguments themselves are real (Mistral-derived
/// from the actual source content), just not force-shown up front.
/// Extracted from the retired `ActionDetailCard` — generic, no dependency
/// on any specific action/opportunity model.
class ProsConsExpansion extends StatelessWidget {
  const ProsConsExpansion({
    required this.prosTitle,
    required this.consTitle,
    required this.pros,
    required this.cons,
    super.key,
  });

  final String prosTitle;
  final String consTitle;
  final List<String> pros;
  final List<String> cons;

  @override
  Widget build(BuildContext context) {
    // ExpansionTile paints ink splashes on the nearest Material ancestor —
    // wrap it in its own transparent Material so that ancestor is this
    // widget, not an opaque DecoratedBox further up.
    return Material(
      type: MaterialType.transparency,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(bottom: 4),
          title: Text(
            'Argumente dafür & dagegen',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: AppColors.ink,
                  fontWeight: FontWeight.w700,
                ),
          ),
          children: [
            _ProsConsBody(
              prosTitle: prosTitle,
              consTitle: consTitle,
              pros: pros,
              cons: cons,
            ),
          ],
        ),
      ),
    );
  }
}

class _ProsConsBody extends StatelessWidget {
  const _ProsConsBody({
    required this.prosTitle,
    required this.consTitle,
    required this.pros,
    required this.cons,
  });

  final String prosTitle;
  final String consTitle;
  final List<String> pros;
  final List<String> cons;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = [
          if (pros.isNotEmpty)
            Expanded(
              child: _ArgumentList(
                title: prosTitle,
                points: pros,
                icon: Icons.add_circle_outline,
                color: AppColors.green,
              ),
            ),
          if (cons.isNotEmpty)
            Expanded(
              child: _ArgumentList(
                title: consTitle,
                points: cons,
                icon: Icons.remove_circle_outline,
                color: AppColors.amberText,
              ),
            ),
        ];
        if (constraints.maxWidth < 420 && columns.length > 1) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              columns[0].child,
              const SizedBox(height: 10),
              columns[1].child,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < columns.length; i++) ...[
              if (i > 0) const SizedBox(width: 10),
              columns[i],
            ],
          ],
        );
      },
    );
  }
}

class _ArgumentList extends StatelessWidget {
  const _ArgumentList({
    required this.title,
    required this.points,
    required this.icon,
    required this.color,
  });

  final String title;
  final List<String> points;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppColors.mutedText,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                ),
          ),
          const SizedBox(height: 8),
          for (final point in points)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, size: 16, color: color),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      point,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.ink,
                            height: 1.3,
                          ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
