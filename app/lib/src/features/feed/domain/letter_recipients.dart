/// Who a letter about a council decision goes to: the members of the bodies
/// preparing or taking the decision, reached through their Fraktion's
/// office. Offices come alphabetically from the server and are all
/// pre-selected; no party comes first by design. District and village
/// councils come with names only, so [offices] is empty for them.
class LetterRecipients {
  const LetterRecipients({
    this.bodies = const [],
    this.members = const [],
    this.offices = const [],
  });

  factory LetterRecipients.fromJson(Map<String, Object?> json) {
    List<Map<String, Object?>> list(String key) =>
        (json[key] as List<Object?>? ?? const [])
            .whereType<Map<String, Object?>>()
            .toList();
    return LetterRecipients(
      bodies: (json['bodies'] as List<Object?>? ?? const []).cast<String>(),
      members: [
        for (final m in list('members'))
          CouncilMember(
            name: m['name'] as String,
            fraktion: m['fraktion'] as String?,
          ),
      ],
      offices: [
        for (final o in list('offices'))
          FraktionOffice(
            fraktion: o['fraktion'] as String,
            email: o['email'] as String?,
          ),
      ],
    );
  }

  final List<String> bodies;
  final List<CouncilMember> members;
  final List<FraktionOffice> offices;
}

class CouncilMember {
  const CouncilMember({required this.name, this.fraktion});

  final String name;
  final String? fraktion;
}

class FraktionOffice {
  const FraktionOffice({required this.fraktion, this.email});

  final String fraktion;
  // Null when the office address is not known yet.
  final String? email;
}
