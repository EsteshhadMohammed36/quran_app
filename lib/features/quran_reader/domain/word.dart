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

  const Word({
    required this.surahId,
    required this.ayahNumber,
    required this.wordPosition,
    required this.wordKey,
    required this.wordIndex,
    required this.text,
  });

  /// The `surah:ayah` identifier this word belongs to (spec §9: tapping
  /// any word resolves to this, then selects/highlights the whole ayah —
  /// never just the tapped word).
  String get ayahKey => '$surahId:$ayahNumber';

  factory Word.fromMap(Map<String, Object?> map) {
    return Word(
      surahId: map['surah_id'] as int,
      ayahNumber: map['ayah_number'] as int,
      wordPosition: map['word_position'] as int,
      wordKey: map['word_key'] as String,
      wordIndex: map['word_index'] as int,
      text: map['text'] as String,
    );
  }
}
