import '../../../core/database/app_database.dart';
import '../domain/audio_repository.dart';
import '../domain/audio_segment.dart';
import '../domain/audio_track.dart';
import '../domain/reciter.dart';

/// SQLite-backed [AudioRepository]. `getReciters` reads the distinct
/// reciter set straight off `audio_assets` (see [Reciter]'s doc comment —
/// there is no separate `reciters` table). `getAyahAudio`/`getSegments`
/// both key off `audio_id`, which is built the same way ingestion built it
/// (`'$reciterId:$ayahKey'`) — a plain primary-key lookup, no join needed.
class SqliteAudioRepository implements AudioRepository {
  final AppDatabase _appDatabase;

  SqliteAudioRepository({AppDatabase? appDatabase})
      : _appDatabase = appDatabase ?? AppDatabase.instance;

  @override
  Future<List<Reciter>> getReciters() async {
    final db = await _appDatabase.database;
    final rows = await db.query(
      'audio_assets',
      distinct: true,
      columns: ['reciter_id', 'reciter_name'],
    );
    return rows.map(Reciter.fromMap).toList();
  }

  @override
  Future<AudioTrack?> getAyahAudio(String reciterId, String ayahKey) async {
    final db = await _appDatabase.database;
    final rows = await db.query(
      'audio_assets',
      where: 'audio_id = ?',
      whereArgs: ['$reciterId:$ayahKey'],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return AudioTrack.fromMap(rows.first);
  }

  @override
  Future<List<AudioSegment>> getSegments(
    String reciterId,
    String ayahKey,
  ) async {
    final db = await _appDatabase.database;
    final rows = await db.query(
      'audio_segments',
      where: 'audio_id = ?',
      whereArgs: ['$reciterId:$ayahKey'],
      orderBy: 'segment_index ASC',
    );
    return rows.map(AudioSegment.fromMap).toList();
  }
}
