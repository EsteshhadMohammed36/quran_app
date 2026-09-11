/// `tafsir_sources.source_id` for Iraab Al-Muyassar (Prompt 11) — the one
/// source among the three that's genuinely syntactic/grammatical analysis
/// (i'rab) rather than general commentary. Spec §13 requires grammar
/// analysis to be kept separate from Tafsir and from Morphology, and to
/// name its data source explicitly; the Ayah Context Sheet's "الإعراب"
/// study tab (Prompt 12) reads this same already-ingested source directly
/// rather than duplicating it into a second table, per CLAUDE.md rule #4
/// (one canonical source per feature/no duplicated data).
const String iraabMuyassarSourceId = 'tafsir-iraab-muyassar-ar';

/// A row of `tafsir_sources` (spec §15). Key: [sourceId].
///
/// The registry of tafsir sources available in the app (spec §11.2
/// `TafsirRepository.getSources()`) — currently Ibn Kathir, As-Saadi, and
/// Iraab Al-Muyassar, all Arabic (Prompt 11).
class TafsirSource {
  final String sourceId;
  final String name;
  final String? language;
  final String? author;

  const TafsirSource({
    required this.sourceId,
    required this.name,
    this.language,
    this.author,
  });

  factory TafsirSource.fromMap(Map<String, Object?> map) {
    return TafsirSource(
      sourceId: map['source_id'] as String,
      name: map['name'] as String,
      language: map['language'] as String?,
      author: map['author'] as String?,
    );
  }
}
