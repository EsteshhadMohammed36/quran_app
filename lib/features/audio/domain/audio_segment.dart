/// One row of `audio_segments` (schema.dart) — one timed slice of an
/// [AudioTrack]'s playback, used to drive synchronized word highlighting
/// (spec §14). Key: `(audioId, segmentIndex)`.
///
/// [segmentIndex] is the segment's own 0-based position in the
/// recitation's timing array for that ayah, NOT [wordKey]'s word
/// position — a reciter can audibly repeat a phrase mid-ayah, which
/// otherwise duplicates a word position within one ayah's segment list
/// (see schema.dart's `audio_segments` doc comment). [wordKey] is `null`
/// when this segment doesn't resolve to a real word (e.g. the ayah-end
/// marker, or a rare extra trailing segment some sources include) — the
/// UI simply has nothing to highlight for that segment, rather than this
/// being an ingestion gap.
class AudioSegment {
  final String audioId;
  final int segmentIndex;
  final String? wordKey;
  final String? ayahKey;
  final int startMs;
  final int endMs;

  const AudioSegment({
    required this.audioId,
    required this.segmentIndex,
    this.wordKey,
    this.ayahKey,
    required this.startMs,
    required this.endMs,
  });

  factory AudioSegment.fromMap(Map<String, Object?> map) {
    return AudioSegment(
      audioId: map['audio_id'] as String,
      segmentIndex: map['segment_index'] as int,
      wordKey: map['word_key'] as String?,
      ayahKey: map['ayah_key'] as String?,
      startMs: map['start_ms'] as int,
      endMs: map['end_ms'] as int,
    );
  }

  /// True when [positionMs] falls within this segment's own time range —
  /// the check [AudioProvider] runs on every playback-position update to
  /// resolve "which segment is playing right now" (spec §14's
  /// AudioController: "-> resolve current segment -> map to word/ayah").
  bool contains(int positionMs) => positionMs >= startMs && positionMs < endMs;
}
