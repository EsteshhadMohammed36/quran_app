/// A row of `words` (spec §15). Key: `(surahId, ayahNumber, wordPosition)`.
///
/// [text] is canonical QPC V2 glyph text — despite the name, these are
/// page-specific presentation-form glyphs tied to that page's font, not
/// generic Unicode Uthmani text (see tool/resource_manifest_seed.dart doc
/// comments). Never transform it (CLAUDE.md rule #1).
class Word {
  final int surahId;
  final int ayahNumber;
  final int wordPosition;
  final String wordKey;
  final int wordIndex;
  final String text;

  /// 'word' (a real Quran word) or 'end_marker' (the circled-ayah-number
  /// ornament every ayah ends with — see `schema.dart`'s `words` table doc
  /// comment and `tool/ingest_quran_data.dart`'s `_buildWords`). Still a
  /// real row here because Mushaf rendering must show it (rule #2), but
  /// [isAyahEndMarker] lets word-level *linguistic* features (Morphology,
  /// spec §12) exclude it instead of treating it as an analyzable word.
  final String wordType;

  const Word({
    required this.surahId,
    required this.ayahNumber,
    required this.wordPosition,
    required this.wordKey,
    required this.wordIndex,
    required this.text,
    this.wordType = 'word',
  });

  /// The `surah:ayah` identifier this word belongs to (spec §9: tapping
  /// any word resolves to this, then selects/highlights the whole ayah —
  /// never just the tapped word).
  String get ayahKey => '$surahId:$ayahNumber';

  /// True for the ayah-end ornament row, not a real Quran word — see
  /// [wordType]'s doc comment.
  bool get isAyahEndMarker => wordType == 'end_marker';

  factory Word.fromMap(Map<String, Object?> map) {
    return Word(
      surahId: map['surah_id'] as int,
      ayahNumber: map['ayah_number'] as int,
      wordPosition: map['word_position'] as int,
      wordKey: map['word_key'] as String,
      wordIndex: map['word_index'] as int,
      text: map['text'] as String,
      wordType: map['word_type'] as String? ?? 'word',
    );
  }
}
