import 'civic_action.dart';

/// A/B/C, ranked for the "does this topic have at least one live window via
/// any option" aggregation below — see the backend's merge.py module
/// docstring for why this is an *existential* check ("does ≥1 option have a
/// live reason"), not a claim that one mechanism is "more urgent" than
/// another.
const _stateRank = {'A': 3, 'B': 2, 'C': 1};

/// A real-world topic with the engagement options (petition, letter) the
/// pipelines found for it. Grouping key is `topicId` (assigned server-side
/// by fingerprint matching, see backend/.../pipeline/merge.py) — never
/// action type, so a topic can carry any mix of options, unranked.
class Topic {
  const Topic({
    required this.topicId,
    required this.title,
    required this.summary,
    required this.proArgumente,
    required this.contraArgumente,
    required this.engagementState,
    required this.stateReason,
    required this.score,
    required this.reasons,
    required this.werteMatchPercent,
    required this.deadline,
    required this.options,
  });

  final String topicId;
  final String title;
  final String summary;
  final List<String> proArgumente;
  final List<String> contraArgumente;
  // Why this topic is relevant to *this* user specifically — computed by
  // LocalFeedScorer (device-side, from the value profile), e.g. "Passt zu
  // deinen Werten." Same headline option as title/summary, for the same
  // cosmetic-tie-break reason. Shown on the topic *detail*, not the feed
  // list — see topic_detail_dialog.dart.
  final List<String> reasons;
  final int? werteMatchPercent;
  // Only ever sourced from a *petition* option — see `_petitionDeadline`.
  // A letter option's `deadline` is really "date of latest associated
  // Vorgang document" (see specs/data/ingestion-pipeline.md), not a real
  // deadline; showing a countdown against it would be exactly the kind of
  // misleading almost-fact this app is trying not to show.
  final DateTime? deadline;
  // Existential aggregate across options — max(STATE_RANK), with the
  // specific, honest reason from whichever option earned it. Every option
  // also keeps and displays its own state/reason individually — this is a
  // headline, not a replacement.
  final String engagementState;
  final String? stateReason;
  final int score;
  final List<ActionRecommendation> options;
}

/// Groups already-scored recommendations (output of `LocalFeedScorer`,
/// unchanged) into topics by `topicId`, sorted by topic score descending.
/// Pure presentation-layer transform — no new scoring, no ranking of
/// options by type.
List<Topic> groupIntoTopics(List<ActionRecommendation> scored) {
  final byTopic = <String, List<ActionRecommendation>>{};
  for (final rec in scored) {
    byTopic.putIfAbsent(rec.action.topicId, () => []).add(rec);
  }

  final topics = byTopic.entries.map((entry) {
    final options = entry.value;
    // Cosmetic tie-break for headline text: fingerprint-matched options
    // already have near-identical titles, so which one "wins" here isn't a
    // ranking claim — just pick the option most relevant to this user.
    final headline = options.reduce((a, b) => a.score >= b.score ? a : b);
    // Separate, existential pick for state/reason: does ANY option have a
    // live window right now, and if so, what's its own honest reason.
    final urgent = options.reduce(
      (a, b) =>
          _rank(a.action.engagementState) >= _rank(b.action.engagementState)
              ? a
              : b,
    );
    final score = options.map((o) => o.score).reduce((a, b) => a > b ? a : b);

    return Topic(
      topicId: entry.key,
      title: headline.action.title,
      summary: headline.action.summary,
      proArgumente: headline.action.proArgumente,
      contraArgumente: headline.action.contraArgumente,
      engagementState: urgent.action.engagementState,
      stateReason: urgent.action.stateReason,
      score: score,
      reasons: headline.reasons,
      werteMatchPercent: headline.werteMatchPercent,
      deadline: _petitionDeadline(options),
      options: options,
    );
  }).toList();

  topics.sort((a, b) => b.score.compareTo(a.score));
  return topics;
}

int _rank(String state) => _stateRank[state] ?? 0;

/// The first petition option's deadline, if any — deliberately never a
/// letter option's `deadline` (see `Topic.deadline`'s doc comment).
DateTime? _petitionDeadline(List<ActionRecommendation> options) {
  for (final option in options) {
    final deadline = option.action.deadline;
    if (optionKindOf(option.action) == OptionKind.petition &&
        deadline != null) {
      return deadline;
    }
  }
  return null;
}

/// Option kind for MVP — petition or letter. Anfrage is a variant inside
/// the letter flow (see `LetterRequest.type`), not a separate top-level
/// option; anything else the pipeline doesn't currently produce falls back
/// to "letter" too.
enum OptionKind { petition, letter }

OptionKind optionKindOf(CivicAction action) {
  return action.actionType == 'petition_signature'
      ? OptionKind.petition
      : OptionKind.letter;
}
