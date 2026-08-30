import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show ByteData, rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// Opens the single local SQLite database described by [schema.dart]
/// (spec §15 tables + §15.1 indexes).
///
/// This class only owns database lifecycle (open, first-run seeding,
/// version). It intentionally exposes no query methods — reads/writes
/// belong in the per-feature repositories (spec §17/§18), which depend on
/// this only to obtain a [Database] handle.
///
/// On first run it copies the pre-built, pre-populated database bundled at
/// [_bundledDatabaseAssetPath] (produced by `tool/ingest_quran_data.dart`,
/// spec §23) into the app's documents directory, rather than creating an
/// empty schema and ingesting Quran data on-device. See CLAUDE.md "Current
/// phase" for why this shape was chosen.
class AppDatabase {
  AppDatabase._internal();

  static final AppDatabase instance = AppDatabase._internal();

  static const String _databaseFileName = 'quran_app.db';
  static const String _bundledDatabaseAssetPath = 'assets/database/quran.db';
  static const int _databaseVersion = 1;

  Database? _database;

  Future<Database> get database async {
    return _database ??= await _open();
  }

  Future<Database> _open() async {
    final Directory appDocumentsDir = await getApplicationDocumentsDirectory();
    final String path = p.join(appDocumentsDir.path, _databaseFileName);

    if (!await databaseExists(path)) {
      await Directory(p.dirname(path)).create(recursive: true);
      final ByteData asset = await rootBundle.load(_bundledDatabaseAssetPath);
      final Uint8List bytes = asset.buffer.asUint8List(
        asset.offsetInBytes,
        asset.lengthInBytes,
      );
      await File(path).writeAsBytes(bytes, flush: true);
    }

    return openDatabase(
      path,
      version: _databaseVersion,
      onConfigure: (db) async {
        // Required for FOREIGN KEY constraints declared in schema.dart to
        // actually be enforced by SQLite.
        await db.execute('PRAGMA foreign_keys = ON;');
      },
    );
  }
}
