/// A reciter available for playback (spec §14/§17.1/§18).
///
/// Not its own table in the schema (§15's table list has no `reciters`
/// row) — `audio_assets` already carries `reciter_id`/`reciter_name` on
/// every row, so [SqliteAudioRepository.getReciters] reads the distinct
/// set from there instead of duplicating that data in a second table
/// (CLAUDE.md rule #4: one canonical source per feature).
class Reciter {
  final String reciterId;
  final String reciterName;

  const Reciter({required this.reciterId, required this.reciterName});

  factory Reciter.fromMap(Map<String, Object?> map) {
    return Reciter(
      reciterId: map['reciter_id'] as String,
      reciterName: map['reciter_name'] as String,
    );
  }
}
