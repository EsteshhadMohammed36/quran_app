/// A row of `surahs` (spec §15). Key: [surahId].
class Surah {
  final int surahId;
  final String nameArabic;
  final String? nameEnglish;
  final String? nameTransliteration;
  final String? revelationPlace;
  final int ayahCount;

  const Surah({
    required this.surahId,
    required this.nameArabic,
    this.nameEnglish,
    this.nameTransliteration,
    this.revelationPlace,
    required this.ayahCount,
  });

  factory Surah.fromMap(Map<String, Object?> map) {
    return Surah(
      surahId: map['surah_id'] as int,
      nameArabic: map['name_arabic'] as String,
      nameEnglish: map['name_english'] as String?,
      nameTransliteration: map['name_transliteration'] as String?,
      revelationPlace: map['revelation_place'] as String?,
      ayahCount: map['ayah_count'] as int,
    );
  }
}
