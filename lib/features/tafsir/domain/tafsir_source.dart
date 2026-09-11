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
