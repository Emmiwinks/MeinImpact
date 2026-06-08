class MdbOption {
  const MdbOption({
    required this.wahlkreisNr,
    required this.wahlkreisName,
    required this.mdbName,
    required this.mdbParty,
    this.mdbLink,
  });

  factory MdbOption.fromJson(Map<String, Object?> json) {
    return MdbOption(
      wahlkreisNr: json['wahlkreis_nr'] as int,
      wahlkreisName: json['wahlkreis_name'] as String,
      mdbName: json['mdb_name'] as String,
      mdbParty: json['mdb_party'] as String,
      mdbLink: json['mdb_link'] as String?,
    );
  }

  final int wahlkreisNr;
  final String wahlkreisName;
  final String mdbName;
  final String mdbParty;
  final String? mdbLink;
}
