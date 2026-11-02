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

/// What the user set by hand for a topic in "Deine Themen". Absent = normal
/// (only what was learned counts).
enum InterestLevel { less, more }

/// On-device interest per topic tag (the backend's fixed taxonomy), learned
/// from behaviour. -maxWeight..+maxWeight, 0 = neutral. Never leaves the
/// device and only reorders the feed, never hides anything.
///
/// This holds data only; every tuning number comes from the [InterestConfig]
/// passed to each call. Weights drift back to neutral with the config's
/// half-life, so old interests fade instead of locking the feed in. Decay is
/// applied lazily: [asOf] is the moment the stored weights were last current.
///
/// [manual] holds what the user set by hand. It does not decay (a "mehr"
/// should not fade after two weeks) and is added on top of what was learned.
class InterestWeights {
  const InterestWeights({
    this.weights = const {},
    this.asOf,
    this.manual = const {},
  });

  factory InterestWeights.fromJson(Map<String, Object?> json) {
    final raw = json['weights'] as Map<String, Object?>? ?? {};
    final asOf = json['as_of'] as String?;
    final manualRaw = json['manual'] as Map<String, Object?>? ?? {};
    return InterestWeights(
      weights: raw.map((k, v) => MapEntry(k, (v as num).toDouble())),
      asOf: asOf == null ? null : DateTime.tryParse(asOf),
      manual: {
        for (final MapEntry(:key, :value) in manualRaw.entries)
          if (InterestLevel.values.asNameMap()[value] case final level?)
            key: level,
      },
    );
  }

  final Map<String, double> weights;
  final DateTime? asOf;
  final Map<String, InterestLevel> manual;

  bool hasSignal(DateTime now, InterestConfig config) {
    final tags = {...weights.keys, ...manual.keys};
    return tags.any(
      (tag) => weightOf(tag, now, config).abs() >= config.neutralBand,
    );
  }

  /// Effective weight: learned (decayed) plus the manual level, clamped.
  double weightOf(String tag, DateTime now, InterestConfig config) {
    final level = manual[tag];
    final manualValue = switch (level) {
      InterestLevel.more => config.manualMore,
      InterestLevel.less => config.manualLess,
      null => 0.0,
    };
    return (learnedOf(tag, now, config) + manualValue)
        .clamp(-config.maxWeight, config.maxWeight);
  }

  /// What behaviour taught, decayed to [now], without the manual level.
  double learnedOf(String tag, DateTime now, InterestConfig config) {
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
      for (final tag in weights.keys) tag: learnedOf(tag, now, config),
    };
    for (final tag in unique) {
      updated[tag] = ((updated[tag] ?? 0) + share)
          .clamp(-config.maxWeight, config.maxWeight);
    }
    return InterestWeights(weights: updated, asOf: now, manual: manual);
  }

  /// A copy with [tag] set by hand to [level] (null = back to normal).
  InterestWeights withManual(String tag, InterestLevel? level) {
    return InterestWeights(
      weights: weights,
      asOf: asOf,
      manual: {
        for (final MapEntry(:key, :value) in manual.entries)
          if (key != tag) key: value,
        if (level != null) tag: level,
      },
    );
  }

  Map<String, Object?> toJson() => {
        'weights': weights,
        'as_of': asOf?.toIso8601String(),
        'manual': {
          for (final MapEntry(:key, :value) in manual.entries) key: value.name,
        },
      };

  static double _decayFactor(DateTime since, DateTime now, Duration halfLife) {
    final elapsed = now.difference(since);
    // A clock set back must not amplify weights.
    if (elapsed.isNegative) return 1;
    return pow(0.5, elapsed.inSeconds / halfLife.inSeconds).toDouble();
  }
}
