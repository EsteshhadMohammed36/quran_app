import 'audio_segment.dart';
import 'audio_track.dart';
import 'reciter.dart';

/// Domain interface for the Audio/Recitation module (spec §14/§18) — exact
/// method set spec §18 specifies.
///
/// UI widgets depend on this, never on raw SQLite rows directly (spec §17).
abstract class AudioRepository {
  Future<List<Reciter>> getReciters();

  /// The reciter's recording of [ayahKey], or `null` if this reciter has no
  /// recording for it (not expected once a reciter is fully ingested, but
  /// the interface allows for a reciter with partial coverage).
  Future<AudioTrack?> getAyahAudio(String reciterId, String ayahKey);

  /// [reciterId]'s timing segments for [ayahKey], ordered by
  /// `segment_index` (i.e. playback order) — used to drive synchronized
  /// word highlighting as [AudioProvider] tracks playback position.
  Future<List<AudioSegment>> getSegments(String reciterId, String ayahKey);
}
