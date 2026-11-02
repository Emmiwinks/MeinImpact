import 'lebenslagen_catalog.g.dart';

/// One entry of the Lebenslagen catalog: a life situation, identity or
/// occupation a user can mark as "das ist mir wichtig" (one relation only:
/// affected, knowing someone affected and caring are not distinguished).
///
/// The catalog is generated from the backend's `ai/lebenslagen.py`
/// (`backend/scripts/export_lebenslagen.py`); ids must match the
/// `lebenslagen` the server tags opportunities with.
class Lebenslage {
  const Lebenslage({
    required this.id,
    required this.label,
    required this.area,
    this.isPrivate = false,
    this.synonyms = const [],
  });

  final String id;
  final String label;
  final String area;
  // GDPR Art. 9 categories (sexual identity, religion, origin, health,
  // disability). A data-handling rule, not a judgment: such an entry is
  // never named in the profile overview or on a feed card.
  final bool isPrivate;
  // Lower-case search terms ("erzieherin" finds the Kita occupation).
  final List<String> synonyms;
}

final Map<String, Lebenslage> lebenslageById = {
  for (final item in kLebenslagen) item.id: item,
};
