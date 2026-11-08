import 'letter_recipients.dart';
import 'mdb.dart';
import 'opportunity.dart';

/// The feed's data boundary. "What this means for you" is precomputed
/// server-side (`personalImpactSnippets`), so one pool request is all the
/// feed needs.
abstract interface class OpportunityRepository {
  /// Returns every open opportunity, unordered. The caller ranks on-device
  /// (see `OpportunityRelevanceRanker`), since the server never sees either
  /// profile.
  Future<List<Opportunity>> pool();

  Future<List<MdbOption>> lookupMdb(String plz);

  /// Streams an AI-drafted letter about a council decision, chunk by chunk.
  /// [notes] is what the user typed for the AI; nothing from the profile is
  /// sent.
  Stream<String> streamLetter(String opportunityId, {String? notes});

  /// Who a letter about a council decision goes to.
  Future<LetterRecipients> letterRecipients(String opportunityId);
}
