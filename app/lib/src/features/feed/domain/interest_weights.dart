import 'dart:math';

import 'interest_config.dart';

/// What the user did with an opportunity. How strongly each counts is set
/// in [InterestConfig].
enum InterestSignal {
  // Opened the detail view.
  opened,
  // Followed the call to action to the registry.
  acted,
}

/// On-device interest per topic tag (the backend's fixed taxonomy), learned
/// from behaviour. -maxWeight..+maxWeight, 0 = neutral. Never leaves the
/// device and only reorders the feed, never hides anything.
///
/// This holds data only; every tuning number comes from the [InterestConfig]
/// passed to each call. Weights drift back to neutral with the config's
/// half-life, so old interests fade instead of locking the feed in. Decay is
/// applied lazily: [asOf] is the moment the stored weights were last current.
class InterestWeights {
  const InterestWeights({this.weights = const {}, this.asOf});

  factory InterestWeights.fromJson(Map<String, Object?> json) {
    final raw = json['weights'] as Map<String, Object?>? ?? {};
    final asOf = json['as_of'] as String?;
    return InterestWeights(
      weights: raw.map((k, v) => MapEntry(k, (v as num).toDouble())),
      asOf: asOf == null ? null : DateTime.tryParse(asOf),
    );
  }

  final Map<String, double> weights;
  final DateTime? asOf;

  bool hasSignal(DateTime now, InterestConfig config) => weights.keys
      .any((tag) => weightOf(tag, now, config).abs() >= config.neutralBand);

  double weightOf(String tag, DateTime now, InterestConfig config) {
    final stored = weights[tag];
    final since = asOf;
    if (stored == null || since == null) return 0;
    return stored * _decayFactor(since, now, config.halfLife);
  }

  /// The strongest opinion among [tags] (largest magnitude, sign kept), so a
  /// card with one loved tag is not diluted by its other tags.
  double interestIn(
    Iterable<String> tags,
    DateTime now,
    InterestConfig config,
  ) {
    var strongest = 0.0;
    for (final tag in tags) {
      final w = weightOf(tag, now, config);
      if (w.abs() > strongest.abs()) strongest = w;
    }
    return strongest;
  }

  /// True when the user has no opinion about any of [tags] yet.
  bool isUnexplored(
    Iterable<String> tags,
    DateTime now,
    InterestConfig config,
  ) =>
      tags.every(
        (tag) => weightOf(tag, now, config).abs() < config.neutralBand,
      );

  /// The liked tag of [tags] to name as the reason for ranking a card up,
  /// or null when none is strong enough.
  String? reasonTag(
    Iterable<String> tags,
    DateTime now,
    InterestConfig config,
  ) {
    String? best;
    var bestWeight = config.reasonThreshold;
    for (final tag in tags) {
      final w = weightOf(tag, now, config);
      if (w >= bestWeight) {
        best = tag;
        bestWeight = w;
      }
    }
    return best;
  }

  /// Weights after [signal] on an opportunity with [tags]. The signal is
  /// shared across the tags (divided by sqrt of their count) so a card with
  /// many tags does not inflate all of them.
  InterestWeights record(
    Iterable<String> tags,
    InterestSignal signal,
    DateTime now,
    InterestConfig config,
  ) {
    final unique = tags.toSet();
    if (unique.isEmpty) return this;
    final share = config.deltaFor(signal) / sqrt(unique.length);
    final updated = <String, double>{
      for (final tag in weights.keys) tag: weightOf(tag, now, config),
    };
    for (final tag in unique) {
      updated[tag] = ((updated[tag] ?? 0) + share)
          .clamp(-config.maxWeight, config.maxWeight);
    }
    return InterestWeights(weights: updated, asOf: now);
  }

  Map<String, Object?> toJson() => {
        'weights': weights,
        'as_of': asOf?.toIso8601String(),
      };

  static double _decayFactor(DateTime since, DateTime now, Duration halfLife) {
    final elapsed = now.difference(since);
    // A clock set back must not amplify weights.
    if (elapsed.isNegative) return 1;
    return pow(0.5, elapsed.inSeconds / halfLife.inSeconds).toDouble();
  }
}
