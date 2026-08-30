// ignore_for_file: avoid_print
//
// Data ingestion pipeline (spec §23) for the Phase 0 Mushaf prototype
// resource set (compatibility_group `madinah-v2-qpc-v2-hafs`).
//
// Reads the 4 raw QUL resources from `raw_resources/` (git-ignored, see
// tool/resource_manifest_seed.dart for exactly what/why), transforms field
// names to the app's canonical schema (spec §23.1), runs the integrity
// checks from spec §24, and — only if every check passes — writes a fresh,
// fully-populated SQLite database to `assets/database/quran.db`. That file
// is bundled as a Flutter asset and copied onto the device on first launch
// by `lib/core/database/app_database.dart`, rather than re-ingesting on
// every install (see CLAUDE.md "Current phase" for why this shape was
// chosen over on-device ingestion).
//
// Run from the repo root:
//   dart run tool/ingest_quran_data.dart
//
// Requires the `sqlite3` CLI on PATH (already present via the Android SDK's
// platform-tools on this machine) — used both to read the two downloaded
// SQLite resource files and to write the output database, so this script
// has zero native/FFI Dart dependencies.
//
// CLAUDE.md rule #1: this script must never alter a single character of
// Quran script text. It only (a) copies word glyph text byte-for-byte from
// the QUL script resource into the `words` table, and (b) concatenates
// those unmodified word strings with a plain space to build
// `ayahs.text_uthmani` — no normalization, no substitution, no cleanup.
library;

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:quran_app/core/database/schema.dart';
import 'package:quran_app/core/resource_manifest/resource_manifest_entry.dart';

import 'resource_manifest_seed.dart';

const String _rawResourcesDirName = 'raw_resources';
const String _outputAssetPath = 'assets/database/quran.db';

const String _layoutZipName = 'qpc-v2-15-lines.db.zip';
const String _layoutDbInnerName = 'qpc-v2-15-lines.db';
const String _scriptZipName = 'qpc-v2.db.zip';
const String _scriptDbInnerName = 'qpc-v2.db';
const String _surahNamesZipName = 'quran-metadata-surah-name.json.zip';
const String _surahNamesJsonInnerName = 'quran-metadata-surah-name.json';

const Set<String> _supportedLineTypes = {'ayah', 'surah_name', 'basmallah'};
const int _maxPageNumber = 604;

Future<void> main(List<String> args) async {
  final String repoRoot = _findRepoRoot();
  final Directory rawDir = Directory('$repoRoot/$_rawResourcesDirName');
  if (!rawDir.existsSync()) {
    _fail(
      'raw_resources/ not found at ${rawDir.path}. Download the 4 QUL '
      'resources first (see tool/resource_manifest_seed.dart doc comments).',
    );
  }

  final Directory work = Directory.systemTemp.createTempSync('quran_ingest_');
  try {
    print('Extracting raw resource archives...');
    final File layoutDb = _extractSingleEntry(
      zip: File('${rawDir.path}/$_layoutZipName'),
      entryName: _layoutDbInnerName,
      outDir: work,
    );
    final File scriptDb = _extractSingleEntry(
      zip: File('${rawDir.path}/$_scriptZipName'),
      entryName: _scriptDbInnerName,
      outDir: work,
    );
    final File surahNamesJson = _extractSingleEntry(
      zip: File('${rawDir.path}/$_surahNamesZipName'),
      entryName: _surahNamesJsonInnerName,
      outDir: work,
    );

    print('Reading source data...');
    final List<Map<String, dynamic>> wordRows = _querySqliteJson(
      scriptDb.path,
      'SELECT id, location, surah, ayah, word, text FROM words ORDER BY id;',
    );
    final List<Map<String, dynamic>> pageRows = _querySqliteJson(
      layoutDb.path,
      'SELECT page_number, line_number, line_type, is_centered, '
      'first_word_id, last_word_id, surah_number FROM pages '
      'ORDER BY page_number, line_number;',
    );
    final Map<String, dynamic> surahNamesRaw =
        jsonDecode(surahNamesJson.readAsStringSync()) as Map<String, dynamic>;

    print(
      'Loaded ${wordRows.length} words, ${pageRows.length} mushaf lines, '
      '${surahNamesRaw.length} surah name entries.',
    );

    print('Verifying word glyph text byte-for-byte against source...');
    _verifyWordBytesMatchSource(scriptDb.path, wordRows);
    print('Word glyph text verified byte-for-byte against source.');

    print('Transforming to canonical schema (spec §23.1)...');
    final List<Map<String, Object?>> surahs = _buildSurahs(surahNamesRaw);
    final List<Map<String, Object?>> words = _buildWords(wordRows);
    final List<Map<String, Object?>> ayahs = _buildAyahs(wordRows);
    final List<Map<String, Object?>> mushafLines = _buildMushafLines(
      pageRows,
    );

    print('Running integrity checks (spec §24)...');
    final List<String> failures = _runIntegrityChecks(
      surahs: surahs,
      ayahs: ayahs,
      words: words,
      mushafLines: mushafLines,
    );
    if (failures.isNotEmpty) {
      _fail(
        'Integrity checks failed (${failures.length}):\n'
        '${failures.map((f) => '  - $f').join('\n')}\n'
        'assets/database/quran.db was NOT written/updated.',
      );
    }
    print('All integrity checks passed.');

    final DateTime retrievedAt = DateTime(2026, 8, 30);
    final List<Map<String, Object?>> manifestRows = phase0ResourceManifestSeed
        .map((ResourceManifestEntry e) =>
            e.copyWith(retrievedAt: retrievedAt).toMap())
        .toList();

    print('Building SQL script...');
    final String sql = _buildSqlScript(
      surahs: surahs,
      ayahs: ayahs,
      words: words,
      mushafLines: mushafLines,
      resourceManifest: manifestRows,
    );

    final File tempDb = File('${work.path}/quran.db');
    print('Writing database via sqlite3 CLI...');
    await _runSqliteScript(tempDb.path, sql);

    print('Verifying written database...');
    _verifyWrittenDatabase(
      dbPath: tempDb.path,
      expectedSurahs: surahs.length,
      expectedAyahs: ayahs.length,
      expectedWords: words.length,
      expectedMushafLines: mushafLines.length,
      expectedManifestRows: manifestRows.length,
    );

    final File outputFile = File('$repoRoot/$_outputAssetPath');
    outputFile.parent.createSync(recursive: true);
    tempDb.copySync(outputFile.path);
    print('Wrote ${outputFile.path} (${outputFile.lengthSync()} bytes).');
    print('Ingestion complete.');
  } finally {
    work.deleteSync(recursive: true);
  }
}

// ---------------------------------------------------------------------------
// Extraction
// ---------------------------------------------------------------------------

File _extractSingleEntry({
  required File zip,
  required String entryName,
  required Directory outDir,
}) {
  if (!zip.existsSync()) {
    _fail('Missing raw resource file: ${zip.path}');
  }
  final Archive archive = ZipDecoder().decodeBytes(zip.readAsBytesSync());
  for (final ArchiveFile f in archive) {
    if (f.isFile && f.name == entryName) {
      final File out = File('${outDir.path}/$entryName');
      out.writeAsBytesSync(f.content as List<int>);
      return out;
    }
  }
  _fail(
    'Entry "$entryName" not found in ${zip.path}. Found: '
    '${archive.files.map((f) => f.name).join(", ")}',
  );
}

// ---------------------------------------------------------------------------
// sqlite3 CLI helpers
// ---------------------------------------------------------------------------

List<Map<String, dynamic>> _querySqliteJson(String dbPath, String sql) {
  // stdoutEncoding must be explicit: Process.runSync defaults to the
  // platform's system encoding (on Windows, an ANSI codepage, not UTF-8),
  // which would decode sqlite3's UTF-8 JSON output one byte at a time and
  // silently corrupt any multi-byte character - including every Quran
  // glyph in `words.text` (CLAUDE.md rule #1: never transform Quran text,
  // not even by accident in a helper function).
  final ProcessResult result = Process.runSync(
    'sqlite3',
    [dbPath, '-json', sql],
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
  );
  if (result.exitCode != 0) {
    _fail('sqlite3 query failed on $dbPath:\n$sql\n${result.stderr}');
  }
  final String out = (result.stdout as String).trim();
  if (out.isEmpty) return [];
  return (jsonDecode(out) as List).cast<Map<String, dynamic>>();
}

Future<void> _runSqliteScript(String dbPath, String sql) async {
  final File dbFile = File(dbPath);
  if (dbFile.existsSync()) dbFile.deleteSync();

  // sqlite3 reads the script from stdin when no positional SQL/dot-command
  // arg follows the db path — avoids ever putting a filesystem path into a
  // ".read <path>" dot-command (which mishandles spaces).
  final Process proc = await Process.start('sqlite3', [dbPath]);
  final Future<String> stdoutFuture = proc.stdout.transform(utf8.decoder).join();
  final Future<String> stderrFuture = proc.stderr.transform(utf8.decoder).join();
  proc.stdin.add(utf8.encode(sql));
  await proc.stdin.close();
  final int exitCode = await proc.exitCode;
  final String stderrText = await stderrFuture;
  await stdoutFuture;
  if (exitCode != 0) {
    _fail('sqlite3 failed writing $dbPath (exit $exitCode):\n$stderrText');
  }
  if (stderrText.trim().isNotEmpty) {
    _fail('sqlite3 reported errors writing $dbPath:\n$stderrText');
  }
}

// ---------------------------------------------------------------------------
// Byte-level source integrity check (CLAUDE.md rule #1)
// ---------------------------------------------------------------------------

/// Independently re-reads every word's glyph text from the source db as hex
/// (pure ASCII, immune to any text-encoding mishandling) and compares it
/// against what [wordRows] holds in memory. Catches any transcoding bug
/// (e.g. a process/stream not decoded as UTF-8) that row-count or structural
/// checks can't see, since those would still pass even if every character
/// were silently mangled.
void _verifyWordBytesMatchSource(
  String scriptDbPath,
  List<Map<String, dynamic>> wordRows,
) {
  final List<Map<String, dynamic>> hexRows = _querySqliteJson(
    scriptDbPath,
    'SELECT id, hex(text) AS hex_text FROM words ORDER BY id;',
  );
  if (hexRows.length != wordRows.length) {
    _fail(
      'Byte-integrity check setup mismatch: ${hexRows.length} hex rows vs '
      '${wordRows.length} word rows.',
    );
  }
  for (int i = 0; i < wordRows.length; i++) {
    final int id = wordRows[i]['id'] as int;
    final int hexId = hexRows[i]['id'] as int;
    if (id != hexId) {
      _fail('Byte-integrity check row order mismatch at index $i: $id vs $hexId.');
    }
    final String expectedHex = (hexRows[i]['hex_text'] as String).toUpperCase();
    final String actualHex = _hexOfUtf8(wordRows[i]['text'] as String);
    if (actualHex != expectedHex) {
      _fail(
        'Word id=$id glyph text does not match source byte-for-byte '
        '(CLAUDE.md rule #1). In-memory hex=$actualHex, source hex=$expectedHex.',
      );
    }
  }
}

String _hexOfUtf8(String s) {
  final bytes = utf8.encode(s);
  final buf = StringBuffer();
  for (final b in bytes) {
    buf.write(b.toRadixString(16).padLeft(2, '0').toUpperCase());
  }
  return buf.toString();
}

// ---------------------------------------------------------------------------
// Schema transforms (spec §23.1 naming normalization)
// ---------------------------------------------------------------------------

List<Map<String, Object?>> _buildSurahs(Map<String, dynamic> surahNamesRaw) {
  final List<Map<String, Object?>> result = [];
  for (final entry in surahNamesRaw.entries) {
    final Map<String, dynamic> v = entry.value as Map<String, dynamic>;
    result.add({
      'surah_id': v['id'] as int,
      'name_arabic': v['name_arabic'] as String,
      'name_english': null,
      'name_transliteration': v['name_simple'] as String?,
      'revelation_place': v['revelation_place'] as String?,
      'ayah_count': v['verses_count'] as int,
    });
  }
  result.sort(
    (a, b) => (a['surah_id'] as int).compareTo(b['surah_id'] as int),
  );
  return result;
}

List<Map<String, Object?>> _buildWords(List<Map<String, dynamic>> wordRows) {
  return wordRows
      .map(
        (w) => {
          'surah_id': w['surah'] as int,
          'ayah_number': w['ayah'] as int,
          'word_position': w['word'] as int,
          'word_key': w['location'] as String,
          'word_index': w['id'] as int,
          // Unmodified glyph text from the QUL QPC V2 script, byte-for-byte
          // (CLAUDE.md rule #1). Note: despite the `words.text` name, these
          // are page-specific presentation-form glyphs tied to the QPC V2
          // font, not generic Unicode Uthmani text.
          'text': w['text'] as String,
          'page_number': null,
          'juz_number': null,
          'hizb_number': null,
        },
      )
      .toList();
}

List<Map<String, Object?>> _buildAyahs(List<Map<String, dynamic>> wordRows) {
  // wordRows is already ordered by global word id, which is the Quran's
  // natural reading order, so grouping preserves per-ayah word order.
  final Map<String, List<String>> textBySurahAyah = {};
  for (final w in wordRows) {
    final String key = '${w['surah']}:${w['ayah']}';
    (textBySurahAyah[key] ??= []).add(w['text'] as String);
  }
  final List<Map<String, Object?>> result = [];
  final Set<String> seen = {};
  for (final w in wordRows) {
    final int surah = w['surah'] as int;
    final int ayah = w['ayah'] as int;
    final String key = '$surah:$ayah';
    if (!seen.add(key)) continue;
    result.add({
      'surah_id': surah,
      'ayah_number': ayah,
      'ayah_key': key,
      // Plain-space join of unmodified word glyph strings — concatenation
      // only, no character-level transformation (CLAUDE.md rule #1).
      'text_uthmani': textBySurahAyah[key]!.join(' '),
      'page_number': null,
      'juz_number': null,
      'hizb_number': null,
    });
  }
  result.sort((a, b) {
    final int s = (a['surah_id'] as int).compareTo(b['surah_id'] as int);
    if (s != 0) return s;
    return (a['ayah_number'] as int).compareTo(b['ayah_number'] as int);
  });
  return result;
}

List<Map<String, Object?>> _buildMushafLines(
  List<Map<String, dynamic>> pageRows,
) {
  return pageRows
      .map(
        (p) => {
          'page_number': p['page_number'] as int,
          'line_number': p['line_number'] as int,
          'line_type': p['line_type'] as String,
          'is_centered': p['is_centered'] as int,
          // The source db stores "" (empty string) rather than SQL NULL for
          // these fields on surah_name/basmallah lines — normalize to null.
          'first_word_id': _asIntOrNull(p['first_word_id']),
          'last_word_id': _asIntOrNull(p['last_word_id']),
          'surah_number': _asIntOrNull(p['surah_number']),
        },
      )
      .toList();
}

int? _asIntOrNull(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is String) return value.isEmpty ? null : int.parse(value);
  throw ArgumentError('Unexpected value for nullable int: $value');
}

// ---------------------------------------------------------------------------
// Integrity checks (spec §24)
// ---------------------------------------------------------------------------

List<String> _runIntegrityChecks({
  required List<Map<String, Object?>> surahs,
  required List<Map<String, Object?>> ayahs,
  required List<Map<String, Object?>> words,
  required List<Map<String, Object?>> mushafLines,
}) {
  final List<String> failures = [];

  // --- Quran integrity ---
  final Set<int> surahIds = surahs.map((s) => s['surah_id'] as int).toSet();
  if (surahIds.length != 114 || surahIds.any((id) => id < 1 || id > 114)) {
    failures.add(
      '114 surahs present: found ${surahIds.length} distinct surah_id(s).',
    );
  }

  final Map<int, int> ayahCountBySurah = {
    for (final s in surahs) s['surah_id'] as int: s['ayah_count'] as int,
  };
  final Map<String, List<int>> wordPositionsByAyah = {};
  for (final w in words) {
    final String key = '${w['surah_id']}:${w['ayah_number']}';
    (wordPositionsByAyah[key] ??= []).add(w['word_position'] as int);
  }
  final Map<int, int> actualAyahCountBySurah = {};
  final Set<String> ayahKeysSeen = {};
  for (final a in ayahs) {
    final int surahId = a['surah_id'] as int;
    final String key = a['ayah_key'] as String;
    if (!ayahKeysSeen.add(key)) {
      failures.add('Duplicate (surah_id, ayah_number): $key');
    }
    actualAyahCountBySurah[surahId] = (actualAyahCountBySurah[surahId] ?? 0) + 1;
    if (!surahIds.contains(surahId)) {
      failures.add('Orphan ayah $key: surah_id $surahId has no surahs row.');
    }
  }
  for (final surahId in surahIds) {
    final int expected = ayahCountBySurah[surahId] ?? -1;
    final int actual = actualAyahCountBySurah[surahId] ?? 0;
    if (expected != actual) {
      failures.add(
        'Surah $surahId ayah count mismatch: surah-names resource says '
        '$expected, but $actual ayah rows were built from the words data.',
      );
    }
  }
  wordPositionsByAyah.forEach((ayahKey, positions) {
    final List<int> sorted = [...positions]..sort();
    final bool sequential = List.generate(
      sorted.length,
      (i) => i + 1,
    ).toString() == sorted.toString();
    if (!sequential) {
      failures.add(
        'Invalid word positions for ayah $ayahKey: $sorted (expected '
        '1..${sorted.length} with no gaps/duplicates).',
      );
    }
    final String surahId = ayahKey.split(':')[0];
    if (!surahIds.contains(int.parse(surahId))) {
      failures.add('Orphan words for ayah $ayahKey: no matching surah.');
    } else if (!ayahKeysSeen.contains(ayahKey)) {
      failures.add('Orphan words for ayah $ayahKey: no matching ayahs row.');
    }
  });

  // --- Mushaf layout ---
  final int minWordIndex =
      words.map((w) => w['word_index'] as int).reduce((a, b) => a < b ? a : b);
  final int maxWordIndex =
      words.map((w) => w['word_index'] as int).reduce((a, b) => a > b ? a : b);
  final bool wordIndexContiguous = maxWordIndex - minWordIndex + 1 == words.length;
  if (!wordIndexContiguous) {
    failures.add(
      'words.word_index is not a contiguous range ($minWordIndex..'
      '$maxWordIndex vs ${words.length} rows) — cannot cheaply verify '
      'mushaf_lines first_word_id/last_word_id reference real words.',
    );
  }

  final Map<int, Set<int>> lineNumbersByPage = {};
  for (final line in mushafLines) {
    final int page = line['page_number'] as int;
    final int lineNo = line['line_number'] as int;
    final String lineType = line['line_type'] as String;

    if (page < 1 || page > _maxPageNumber) {
      failures.add('mushaf_lines page_number out of range: $page');
    }
    (lineNumbersByPage[page] ??= <int>{}).add(lineNo);

    if (!_supportedLineTypes.contains(lineType)) {
      failures.add('Unsupported line_type "$lineType" on page $page line $lineNo.');
    }

    if (lineType == 'ayah') {
      final int? first = line['first_word_id'] as int?;
      final int? last = line['last_word_id'] as int?;
      if (first == null || last == null) {
        failures.add('Ayah line (page $page, line $lineNo) missing word range.');
      } else {
        if (first > last) {
          failures.add(
            'first_word_id > last_word_id on page $page line $lineNo: '
            '$first > $last',
          );
        }
        if (wordIndexContiguous &&
            (first < minWordIndex || last > maxWordIndex)) {
          failures.add(
            'Word range on page $page line $lineNo ($first..$last) falls '
            'outside existing word_index range ($minWordIndex..$maxWordIndex).',
          );
        }
      }
    }

    if (lineType == 'surah_name') {
      final int? surahNumber = line['surah_number'] as int?;
      if (surahNumber == null || !surahIds.contains(surahNumber)) {
        failures.add(
          'surah_name line (page $page, line $lineNo) has invalid '
          'surah_number: $surahNumber',
        );
      }
    }
  }
  lineNumbersByPage.forEach((page, lineNumbers) {
    final int expectedLines =
        mushafLines.where((l) => l['page_number'] == page).length;
    if (lineNumbers.length != expectedLines) {
      failures.add('Duplicate line_number(s) on page $page.');
    }
  });

  return failures;
}

// ---------------------------------------------------------------------------
// SQL generation
// ---------------------------------------------------------------------------

String _sqlLiteral(Object? value) {
  if (value == null) return 'NULL';
  if (value is int) return value.toString();
  if (value is String) return "'${value.replaceAll("'", "''")}'";
  throw ArgumentError('Unsupported SQL literal type: ${value.runtimeType}');
}

String _insertStatement(String table, Map<String, Object?> row) {
  final String columns = row.keys.join(', ');
  final String values = row.values.map(_sqlLiteral).join(', ');
  return 'INSERT INTO $table ($columns) VALUES ($values);';
}

String _buildSqlScript({
  required List<Map<String, Object?>> surahs,
  required List<Map<String, Object?>> ayahs,
  required List<Map<String, Object?>> words,
  required List<Map<String, Object?>> mushafLines,
  required List<Map<String, Object?>> resourceManifest,
}) {
  final StringBuffer sql = StringBuffer();
  sql.writeln('PRAGMA foreign_keys = OFF;'); // enforced at app runtime instead
  for (final statement in createTableStatements) {
    sql.writeln(statement);
  }
  for (final statement in createIndexStatements) {
    sql.writeln(statement);
  }
  sql.writeln('BEGIN TRANSACTION;');
  for (final row in surahs) {
    sql.writeln(_insertStatement('surahs', row));
  }
  for (final row in ayahs) {
    sql.writeln(_insertStatement('ayahs', row));
  }
  for (final row in words) {
    sql.writeln(_insertStatement('words', row));
  }
  for (final row in mushafLines) {
    sql.writeln(_insertStatement('mushaf_lines', row));
  }
  for (final row in resourceManifest) {
    sql.writeln(_insertStatement('resource_manifest', row));
  }
  sql.writeln('COMMIT;');
  return sql.toString();
}

// ---------------------------------------------------------------------------
// Post-write verification
// ---------------------------------------------------------------------------

void _verifyWrittenDatabase({
  required String dbPath,
  required int expectedSurahs,
  required int expectedAyahs,
  required int expectedWords,
  required int expectedMushafLines,
  required int expectedManifestRows,
}) {
  final Map<String, int> expected = {
    'surahs': expectedSurahs,
    'ayahs': expectedAyahs,
    'words': expectedWords,
    'mushaf_lines': expectedMushafLines,
    'resource_manifest': expectedManifestRows,
  };
  for (final entry in expected.entries) {
    final rows = _querySqliteJson(
      dbPath,
      'SELECT COUNT(*) AS c FROM ${entry.key};',
    );
    final int actual = rows.first['c'] as int;
    if (actual != entry.value) {
      _fail(
        'Row count mismatch after write in "${entry.key}": expected '
        '${entry.value}, got $actual.',
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Misc
// ---------------------------------------------------------------------------

String _findRepoRoot() {
  Directory dir = File(Platform.script.toFilePath()).parent;
  while (!File('${dir.path}/pubspec.yaml').existsSync()) {
    final Directory parent = dir.parent;
    if (parent.path == dir.path) {
      _fail('Could not locate repo root (no pubspec.yaml found upwards).');
    }
    dir = parent;
  }
  return dir.path;
}

Never _fail(String message) {
  stderr.writeln('ERROR: $message');
  exit(1);
}
