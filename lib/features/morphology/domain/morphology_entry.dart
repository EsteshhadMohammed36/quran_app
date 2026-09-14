/// One word's linguistic metadata (spec §12/§12.1/§12.2), one row of the
/// `morphology` table (schema.dart) keyed by `(surah_id, ayah_number,
/// word_position)` — the exact key spec §12.1 specifies
/// ("surah + ayah + word_position", example `27:82:4`).
///
/// [root]/[lemma]/[stem] are `null` when the source data genuinely has none
/// for this word (e.g. most particles have no root) — a real linguistic
/// fact, not a missing-data gap (see tool/ingest_quran_data.dart's
/// `_buildMorphology`). [partOfSpeech]/[grammarTags] are always `null` for
/// now: no part-of-speech/grammar-tag resource was found alongside the
/// root/lemma/stem resources on QUL (spec §12.2 "Grammar tags (when
/// available)").
class MorphologyEntry {
  final int surahId;
  final int ayahNumber;
  final int wordPosition;
  final String wordKey;
  final String? root;
  final String? lemma;
  final String? stem;
  final String? partOfSpeech;
  final String? grammarTags;

  const MorphologyEntry({
    required this.surahId,
    required this.ayahNumber,
    required this.wordPosition,
    required this.wordKey,
    this.root,
    this.lemma,
    this.stem,
    this.partOfSpeech,
    this.grammarTags,
  });

  factory MorphologyEntry.fromMap(Map<String, Object?> map) {
    return MorphologyEntry(
      surahId: map['surah_id'] as int,
      ayahNumber: map['ayah_number'] as int,
      wordPosition: map['word_position'] as int,
      wordKey: map['word_key'] as String,
      root: map['root'] as String?,
      lemma: map['lemma'] as String?,
      stem: map['stem'] as String?,
      partOfSpeech: map['part_of_speech'] as String?,
      grammarTags: map['grammar_tags'] as String?,
    );
  }
}
