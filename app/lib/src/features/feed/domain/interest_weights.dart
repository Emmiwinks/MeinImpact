import 'dart:math';

/// What the user did with an opportunity, and how strongly it counts as
/// interest in its topics.
enum InterestSignal {
  // Opened the detail view.
  opened(0.1),
  // Followed the call to action to the registry.
  acted(0.3);

  const InterestSignal(this.delta);
  final double delta;
}

/// On-device interest per topic tag (the backend's fixed taxonomy), learned
/// from behaviour. -1.0 .. +1.0, 0 = neutral. Never leaves the device and
/// only reorders the feed, never hides anything.
///
/// Weights drift back to neutral with a half-life, so old interests fade
/// instead of locking the feed in. Decay is applied lazily: [asOf] is the
/// moment the stored weights were last current.
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

  static const halfLife = Duration(days: 30);
  // Below this a weight counts as "no opinion" (unexplored topic).
  static const neutralBand = 0.05;
  // From this a topic is strong enough to be named as the reason for a card.
  static const reasonThreshold = 0.15;

  final Map<String, double> weights;
  final DateTime? asOf;

  bool hasSignal(DateTime now) =>
      weights.keys.any((tag) => weightOf(tag, now).abs() >= neutralBand);

  double weightOf(String tag, DateTime now) {
    final stored = weights[tag];
    final since = asOf;
    if (stored == null || since == null) return 0;
    return stored * _decayFactor(since, now);
  }

  /// The strongest opinion among [tags] (largest magnitude, sign kept), so a
  /// card with one loved tag is not diluted by its other tags.
  double interestIn(Iterable<String> tags, DateTime now) {
    var strongest = 0.0;
    for (final tag in tags) {
      final w = weightOf(tag, now);
      if (w.abs() > strongest.abs()) strongest = w;
    }
    return strongest;
  }

  /// True when the user has no opinion about any of [tags] yet.
  bool isUnexplored(Iterable<String> tags, DateTime now) =>
      tags.every((tag) => weightOf(tag, now).abs() < neutralBand);

  /// The liked tag of [tags] to name as the reason for ranking a card up,
  /// or null when none is strong enough.
  String? reasonTag(Iterable<String> tags, DateTime now) {
    String? best;
    var bestWeight = reasonThreshold;
    for (final tag in tags) {
      final w = weightOf(tag, now);
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
  ) {
    final unique = tags.toSet();
    if (unique.isEmpty) return this;
    final share = signal.delta / sqrt(unique.length);
    final updated = <String, double>{
      for (final tag in weights.keys) tag: weightOf(tag, now),
    };
    for (final tag in unique) {
      updated[tag] = ((updated[tag] ?? 0) + share).clamp(-1.0, 1.0);
    }
    return InterestWeights(weights: updated, asOf: now);
  }

  Map<String, Object?> toJson() => {
        'weights': weights,
        'as_of': asOf?.toIso8601String(),
      };

  static double _decayFactor(DateTime since, DateTime now) {
    final elapsed = now.difference(since);
    // A clock set back must not amplify weights.
    if (elapsed.isNegative) return 1;
    return pow(0.5, elapsed.inSeconds / halfLife.inSeconds).toDouble();
  }
}
