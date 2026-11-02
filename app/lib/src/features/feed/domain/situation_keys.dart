/// Bridges the Lebenslagen a user picked to the server's per-card
/// `personal_impact_snippets`, which are keyed by the older "field:value"
/// situation keys (backend `taxonomy.TAG_BETROFFENHEIT_KEYS`). Keep both
/// sides in lockstep: a renamed key silently stops matching.
const _snippetKeysByLebenslage = <String, List<String>>{
  'mieter': ['wohnsituation:mieter'],
  'eigentuemer': ['wohnsituation:eigentuemer'],
  'oepnv': ['oepnv_nutzung:true'],
  'autofahrer': ['auto_nutzung:true'],
  'eltern': ['hat_kinder:true'],
  'alleinerziehend': ['hat_kinder:true'],
  'kita_kinder': ['hat_kinder:true'],
  'schulkinder': ['hat_kinder:true'],
  'angestellt': ['erwerbsstatus:angestellt'],
  'selbststaendig': ['erwerbsstatus:selbststaendig'],
  'arbeitssuchend': ['erwerbsstatus:arbeitslos'],
  'buergergeld': ['erwerbsstatus:arbeitslos'],
  'rentner': ['erwerbsstatus:rentner'],
  'studierend': ['erwerbsstatus:schueler_student'],
  'azubi': ['erwerbsstatus:schueler_student'],
  'pflegende_angehoerige': ['pflege_betroffen:true'],
  'migrationshintergrund': ['migrationshintergrund:true'],
  'gefluechtet': ['migrationshintergrund:true'],
};

/// The snippet keys a set of picked Lebenslagen unlocks.
Set<String> snippetKeysFor(Iterable<String> lebenslagen) => {
      for (final id in lebenslagen) ...?_snippetKeysByLebenslage[id],
    };

/// Lebenslagen ids for a profile saved before the catalog existed (the old
/// `betroffenheitsprofil` JSON), so nobody loses their answers on update.
Set<String> lebenslagenFromLegacy(Map<String, Object?> json) {
  return {
    if (json['wohnsituation'] == 'mieter') 'mieter',
    if (json['wohnsituation'] == 'eigentuemer') 'eigentuemer',
    if (json['oepnv_nutzung'] == true) 'oepnv',
    if (json['auto_nutzung'] == true) 'autofahrer',
    if (json['hat_kinder'] == true) 'eltern',
    if (json['pflege_betroffen'] == true) 'pflegende_angehoerige',
    if (json['migrationshintergrund'] == true) 'migrationshintergrund',
    ...switch (json['erwerbsstatus']) {
      'angestellt' => const {'angestellt'},
      'selbststaendig' => const {'selbststaendig'},
      'arbeitslos' => const {'arbeitssuchend'},
      'rentner' => const {'rentner'},
      'schueler_student' => const {'studierend'},
      _ => const <String>{},
    },
  };
}
