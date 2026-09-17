/// One row of `audio_assets` (schema.dart) — one reciter's recording of
/// one ayah (spec §14/§15). Key: `audioId`.
///
/// [filePath] holds a remote `https://` URL, not an on-device file path —
/// see schema.dart's `audio_assets` doc comment for why (the ingested
/// recitation resource is itself only a URL + timing per ayah; playback
/// streams this URL rather than the app bundling recitation audio).
/// [durationMs] is derived at ingestion time from the last segment's own
/// end time (the source's own duration field was empty for every row) —
/// an approximation only, good enough for display before the real audio
/// loads; the audio player itself reports the authoritative duration once
/// playback starts.
class AudioTrack {
  final String audioId;
  final String reciterId;
  final String? reciterName;
  final int? surahId;
  final String? ayahKey;
  final String filePath;
  final String? format;
  final int? durationMs;

  const AudioTrack({
    required this.audioId,
    required this.reciterId,
    this.reciterName,
    this.surahId,
    this.ayahKey,
    required this.filePath,
    this.format,
    this.durationMs,
  });

  factory AudioTrack.fromMap(Map<String, Object?> map) {
    return AudioTrack(
      audioId: map['audio_id'] as String,
      reciterId: map['reciter_id'] as String,
      reciterName: map['reciter_name'] as String?,
      surahId: map['surah_id'] as int?,
      ayahKey: map['ayah_key'] as String?,
      filePath: map['file_path'] as String,
      format: map['format'] as String?,
      durationMs: map['duration_ms'] as int?,
    );
  }
}
