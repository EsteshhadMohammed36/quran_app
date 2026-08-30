import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'schema.dart';

/// Opens/creates the single local SQLite database described by [schema.dart]
/// (spec §15 tables + §15.1 indexes).
///
/// This class only owns database lifecycle (open, schema creation, version).
/// It intentionally exposes no query methods — reads/writes belong in the
/// per-feature repositories (spec §17/§18), which depend on this only to
/// obtain a [Database] handle.
class AppDatabase {
  AppDatabase._internal();

  static final AppDatabase instance = AppDatabase._internal();

  static const String _databaseFileName = 'quran_app.db';
  static const int _databaseVersion = 1;

  Database? _database;

  Future<Database> get database async {
    return _database ??= await _open();
  }

  Future<Database> _open() async {
    final Directory appDocumentsDir = await getApplicationDocumentsDirectory();
    final String path = p.join(appDocumentsDir.path, _databaseFileName);

    return openDatabase(
      path,
      version: _databaseVersion,
      onConfigure: (db) async {
        // Required for FOREIGN KEY constraints declared in schema.dart to
        // actually be enforced by SQLite.
        await db.execute('PRAGMA foreign_keys = ON;');
      },
      onCreate: (db, version) async {
        for (final statement in createTableStatements) {
          await db.execute(statement);
        }
        for (final statement in createIndexStatements) {
          await db.execute(statement);
        }
      },
    );
  }
}
