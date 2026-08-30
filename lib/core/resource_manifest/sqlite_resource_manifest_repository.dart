import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';
import 'resource_manifest_entry.dart';
import 'resource_manifest_repository.dart';

const String _table = 'resource_manifest';

/// SQLite-backed [ResourceManifestRepository].
class SqliteResourceManifestRepository implements ResourceManifestRepository {
  final AppDatabase _appDatabase;

  SqliteResourceManifestRepository({AppDatabase? appDatabase})
      : _appDatabase = appDatabase ?? AppDatabase.instance;

  @override
  Future<void> register(ResourceManifestEntry entry) async {
    _validate(entry);
    final db = await _appDatabase.database;
    await db.insert(
      _table,
      entry.toMap(),
      // A dataset getting a new version/revision re-registers under the
      // same resource_id rather than silently duplicating rows.
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<List<ResourceManifestEntry>> getAll() async {
    final db = await _appDatabase.database;
    final rows = await db.query(_table, orderBy: 'resource_id');
    return rows.map(ResourceManifestEntry.fromMap).toList();
  }

  @override
  Future<ResourceManifestEntry?> getById(String resourceId) async {
    final db = await _appDatabase.database;
    final rows = await db.query(
      _table,
      where: 'resource_id = ?',
      whereArgs: [resourceId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return ResourceManifestEntry.fromMap(rows.first);
  }

  @override
  Future<List<ResourceManifestEntry>> getByCompatibilityGroup(
    String compatibilityGroup,
  ) async {
    final db = await _appDatabase.database;
    final rows = await db.query(
      _table,
      where: 'compatibility_group = ?',
      whereArgs: [compatibilityGroup],
      orderBy: 'resource_id',
    );
    return rows.map(ResourceManifestEntry.fromMap).toList();
  }

  @override
  Future<void> updateStatus(
    String resourceId,
    ResourceManifestStatus status,
  ) async {
    final db = await _appDatabase.database;
    final count = await db.update(
      _table,
      {'status': status.value},
      where: 'resource_id = ?',
      whereArgs: [resourceId],
    );
    if (count == 0) {
      throw StateError(
        'Cannot update status: no resource_manifest row for "$resourceId". '
        'Register it first with ResourceManifestRepository.register().',
      );
    }
  }

  /// Enforces CLAUDE.md rule #4 ("no exceptions, no 'I'll add the manifest
  /// later'") at the code level: a resource cannot be registered without
  /// the identifying/provenance fields the rule actually cares about.
  void _validate(ResourceManifestEntry entry) {
    final missing = <String>[
      if (entry.resourceId.trim().isEmpty) 'resourceId',
      if (entry.resourceName.trim().isEmpty) 'resourceName',
      if (entry.provider.trim().isEmpty) 'provider',
      if (entry.category.trim().isEmpty) 'category',
      if (entry.sourceUrl.trim().isEmpty) 'sourceUrl',
    ];
    if (missing.isNotEmpty) {
      throw ArgumentError(
        'resource_manifest entry is missing required field(s): '
        '${missing.join(', ')}. Every imported dataset needs a complete '
        'manifest entry (spec §16) — fill these in rather than deferring.',
      );
    }
  }
}
