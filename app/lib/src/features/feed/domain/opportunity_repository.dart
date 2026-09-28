import 'mdb.dart';
import 'opportunity.dart';

/// Replaces `ActionRepository`. No `streamDraft`/`getContext` — letters
/// aren't in focus right now (the found opportunity already *is* the
/// action; there's no synthesized "also write a letter about this" step),
/// and "what this means for you" is precomputed server-side
/// (`personalImpactSnippets`), not generated on demand per item.
abstract interface class OpportunityRepository {
  /// Returns the current run's opportunities, unordered — the caller
  /// applies on-device relevance ranking (see
  /// `OpportunityRelevanceRanker`), since the server never sees either
  /// profile.
  Future<List<Opportunity>> pool();

  Future<List<MdbOption>> lookupMdb(String plz);
}
