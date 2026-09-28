/// Concrete personal-situation profile — on-device only, never transmitted
/// (see architecture/dsgvo.md). Distinct from the Werteprofil (ideological
/// axes): this drives *whether* a tag is relevant to this person at all,
/// not how it's framed. Structure mirrors the backend's
/// `TAG_BETROFFENHEIT_KEYS` mapping in `opportunity_extractor.py` — the
/// "field:value" keys produced here must match `personal_impact_snippets`
/// keys on the backend exactly, or nothing will ever match.
enum Wohnsituation { mieter, eigentuemer }

enum Erwerbsstatus {
  angestellt,
  selbststaendig,
  arbeitslos,
  rentner,
  schuelerStudent
}

class Betroffenheitsprofil {
  const Betroffenheitsprofil({
    this.wohnsituation,
    this.oepnvNutzung = false,
    this.autoNutzung = false,
    this.hatKinder = false,
    this.erwerbsstatus,
    this.pflegeBetroffen = false,
    this.migrationshintergrund,
  });

  factory Betroffenheitsprofil.fromJson(Map<String, Object?> json) {
    return Betroffenheitsprofil(
      wohnsituation: _wohnsituationFrom(json['wohnsituation'] as String?),
      oepnvNutzung: json['oepnv_nutzung'] as bool? ?? false,
      autoNutzung: json['auto_nutzung'] as bool? ?? false,
      hatKinder: json['hat_kinder'] as bool? ?? false,
      erwerbsstatus: _erwerbsstatusFrom(json['erwerbsstatus'] as String?),
      pflegeBetroffen: json['pflege_betroffen'] as bool? ?? false,
      migrationshintergrund: json['migrationshintergrund'] as bool?,
    );
  }

  final Wohnsituation? wohnsituation;
  final bool oepnvNutzung;
  final bool autoNutzung;
  final bool hatKinder;
  final Erwerbsstatus? erwerbsstatus;
  final bool pflegeBetroffen;
  // Optional per the spec — null means "not answered", distinct from false.
  final bool? migrationshintergrund;

  bool get isEmpty =>
      wohnsituation == null &&
      !oepnvNutzung &&
      !autoNutzung &&
      !hatKinder &&
      erwerbsstatus == null &&
      !pflegeBetroffen &&
      migrationshintergrund != true;

  /// The "field:value" keys this profile matches — look these up against
  /// an opportunity's `personalImpactSnippets` to find a relevant one.
  /// Keys must match `TAG_BETROFFENHEIT_KEYS`'s values in
  /// `opportunity_extractor.py` exactly.
  Set<String> matchingKeys() {
    return {
      if (wohnsituation != null) 'wohnsituation:${wohnsituation!.name}',
      if (oepnvNutzung) 'oepnv_nutzung:true',
      if (autoNutzung) 'auto_nutzung:true',
      if (hatKinder) 'hat_kinder:true',
      if (erwerbsstatus != null)
        'erwerbsstatus:${_erwerbsstatusKey(erwerbsstatus!)}',
      if (pflegeBetroffen) 'pflege_betroffen:true',
      if (migrationshintergrund == true) 'migrationshintergrund:true',
    };
  }

  /// Short, human-readable lines for the profile's "Über dich" card — real
  /// answers only, never fabricated (replaces the old hardcoded demo
  /// persona in UserProfile).
  List<String> displayLines() {
    return [
      if (wohnsituation == Wohnsituation.mieter) 'Mieter:in',
      if (wohnsituation == Wohnsituation.eigentuemer) 'Eigentümer:in',
      if (erwerbsstatus != null) _erwerbsstatusLabel(erwerbsstatus!),
      if (hatKinder) 'Hat Kinder',
      if (pflegeBetroffen) 'Pflegend tätig',
      if (oepnvNutzung) 'Nutzt ÖPNV',
      if (autoNutzung) 'Nutzt Auto',
    ];
  }

  Map<String, Object?> toJson() {
    return {
      'wohnsituation': wohnsituation?.name,
      'oepnv_nutzung': oepnvNutzung,
      'auto_nutzung': autoNutzung,
      'hat_kinder': hatKinder,
      'erwerbsstatus':
          erwerbsstatus != null ? _erwerbsstatusKey(erwerbsstatus!) : null,
      'pflege_betroffen': pflegeBetroffen,
      'migrationshintergrund': migrationshintergrund,
    };
  }
}

String _erwerbsstatusLabel(Erwerbsstatus status) => switch (status) {
      Erwerbsstatus.angestellt => 'Angestellt',
      Erwerbsstatus.selbststaendig => 'Selbstständig',
      Erwerbsstatus.arbeitslos => 'Arbeitssuchend',
      Erwerbsstatus.rentner => 'Rentner:in',
      Erwerbsstatus.schuelerStudent => 'Schüler:in / Student:in',
    };

String _erwerbsstatusKey(Erwerbsstatus status) {
  // schuelerStudent -> "schueler_student", matching the backend's snake_case
  // key exactly; the rest already match their enum name.
  return status == Erwerbsstatus.schuelerStudent
      ? 'schueler_student'
      : status.name;
}

Wohnsituation? _wohnsituationFrom(String? value) {
  return switch (value) {
    'mieter' => Wohnsituation.mieter,
    'eigentuemer' => Wohnsituation.eigentuemer,
    _ => null,
  };
}

Erwerbsstatus? _erwerbsstatusFrom(String? value) {
  return switch (value) {
    'angestellt' => Erwerbsstatus.angestellt,
    'selbststaendig' => Erwerbsstatus.selbststaendig,
    'arbeitslos' => Erwerbsstatus.arbeitslos,
    'rentner' => Erwerbsstatus.rentner,
    'schueler_student' => Erwerbsstatus.schuelerStudent,
    _ => null,
  };
}
