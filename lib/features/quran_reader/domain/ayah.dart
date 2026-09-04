/// A row of `ayahs` (spec §15). Key: `(surahId, ayahNumber)`.
///
/// [textUthmani] is canonical Quran text — never transform it
/// (CLAUDE.md rule #1).
class Ayah {
  final int surahId;
  final int ayahNumber;
  final String ayahKey;
  final String textUthmani;
  final int? pageNumber;
  final int? juzNumber;
  final int? hizbNumber;

  const Ayah({
    required this.surahId,
    required this.ayahNumber,
    required this.ayahKey,
    required this.textUthmani,
    this.pageNumber,
    this.juzNumber,
    this.hizbNumber,
  });

  factory Ayah.fromMap(Map<String, Object?> map) {
    return Ayah(
      surahId: map['surah_id'] as int,
      ayahNumber: map['ayah_number'] as int,
      ayahKey: map['ayah_key'] as String,
      textUthmani: map['text_uthmani'] as String,
      pageNumber: map['page_number'] as int?,
      juzNumber: map['juz_number'] as int?,
      hizbNumber: map['hizb_number'] as int?,
    );
  }
}
