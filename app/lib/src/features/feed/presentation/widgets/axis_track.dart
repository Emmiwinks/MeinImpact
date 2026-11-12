import 'package:flutter/material.dart';

import '../../../../app/theme/mi_theme.dart';

/// The track of a value axis, shared by the profile's axis blocks and the
/// questionnaire: continuous, only the centre marked, an ink bar from the
/// centre to the marker. [position] runs from -1 (left pole) to +1. Without
/// a [marker] (a question not answered yet) a faint empty ring waits in the
/// centre.
class AxisTrack extends StatelessWidget {
  const AxisTrack({
    required this.position,
    required this.ink,
    required this.stock,
    this.marker = true,
    super.key,
  });

  final double position;
  final Color ink;
  final Color stock;
  final bool marker;

  static const height = 28.0;
  static const markerSize = 28.0;
  static const _bar = 8.0;

  /// The x of [position]'s centre on a track [width] wide; the marker's
  /// centre runs between the two ends of the track.
  static double x(double position, double width) =>
      markerSize / 2 + (width - markerSize) * (position + 1) / 2;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final centre = x(0, width);
          final at = x(position, width);
          return Stack(
            clipBehavior: Clip.none,
            children: [
              // The track.
              Positioned(
                left: 0,
                right: 0,
                top: (height - _bar) / 2,
                height: _bar,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: ink.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(MiRadius.chip),
                  ),
                ),
              ),
              // The centre: "beides gleich". The empty ring takes its place
              // before an answer.
              if (marker)
                Positioned(
                  left: centre - 1.5,
                  top: 2,
                  width: 3,
                  height: height - 4,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: ink.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                )
              else
                Positioned(
                  left: centre - markerSize / 2,
                  top: (height - markerSize) / 2,
                  width: markerSize,
                  height: markerSize,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: ink.withValues(alpha: 0.4),
                        width: 2.5,
                      ),
                    ),
                  ),
                ),
              if (marker) ...[
                // The lean: from the centre to the marker.
                Positioned(
                  left: at < centre ? at : centre,
                  width: (at - centre).abs(),
                  top: (height - _bar) / 2,
                  height: _bar,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: ink,
                      borderRadius: BorderRadius.circular(MiRadius.chip),
                    ),
                  ),
                ),
                Positioned(
                  left: at - markerSize / 2,
                  top: (height - markerSize) / 2,
                  width: markerSize,
                  height: markerSize,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: stock,
                      shape: BoxShape.circle,
                      border: Border.all(color: ink, width: 4),
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
