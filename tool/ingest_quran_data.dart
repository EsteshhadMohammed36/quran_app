// ignore_for_file: avoid_print
//
// Data ingestion pipeline (spec §23) for the Phase 0 Mushaf prototype
// resource set (compatibility_group `madinah-v2-qpc-v2-hafs`) and — since
// Prompt 11 — the Tafsir module (spec §11), and — since Prompt 12 — the
// Morphology module (spec §12).
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
// Prompt 11 added 3 more raw QUL resources (Ibn Kathir, As-Saadi, Iraab
// Al-Muyassar — all Arabic tafsir) into the same single-pass pipeline, so
// the app still bundles exactly one combined database file (spec §15).
//
// Prompt 12 (spec §12) added a further 3 raw QUL resources (word-level
// root/lemma/stem, the "Word by word" variants) into the same pipeline,
// populating the already-existing `morphology` table (schema.dart) with
// one row per `words` row — root/lemma/stem populated where the source
// data has them, NULL otherwise (a word without a root, e.g. most
// particles, isn't an ingestion gap). `part_of_speech`/`grammar_tags`
// stay NULL throughout: no POS/grammar-tag resource was found alongside
// these on QUL (spec §12.2 "(when available)").
//
// Prompt 13 (spec §14) added one more raw QUL resource (a single reciter's
// Ayah-by-Ayah recitation + word-level segment timing), populating the
// already-existing `audio_assets`/`audio_segments` tables (schema.dart).
// That resource is metadata only — an `audio_url` per ayah plus timing
// segments, not the mp3 bytes themselves — so the app streams `audio_url`
// at playback time rather than bundling audio the way the 604 QPC V2 fonts
// were bundled. See tool/resource_manifest_seed.dart's
// `audioModuleResourceManifestSeed` doc comment for two real data-shape
// quirks this resource needed handling for.
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

// --- Tafsir module (Prompt 11, spec §11) ------------------------------------
const String _ibnKathirZipName = 'ar-tafsir-ibn-kathir.db.zip';
const String _ibnKathirDbInnerName = 'ar-tafsir-ibn-kathir.db';
const String _saadiZipName = 'ar-tafseer-al-saddi.db.zip';
const String _saadiDbInnerName = 'ar-tafseer-al-saddi.db';
const String _iraabZipName = 'al-i-rab-al-muyassar.db.zip';
const String _iraabDbInnerName = 'al-i-rab-al-muyassar.db';

// --- Morphology module (Prompt 12, spec §12) --------------------------------
const String _wordRootZipName = 'word-root.db.zip';
const String _wordRootDbInnerName = 'word-root.db';
const String _wordLemmaZipName = 'word-lemma.db.zip';
const String _wordLemmaDbInnerName = 'word-lemma.db';
const String _wordStemZipName = 'word-stem.db.zip';
const String _wordStemDbInnerName = 'word-stem.db';

// --- Audio module (Prompt 13, spec §14) --------------------------------
// QUL's own download names the file after its internal recitation id (953),
// not the resource page id in its URL (118) — both are the same resource,
// see tool/resource_manifest_seed.dart's `audioModuleResourceManifestSeed`.
const String _recitationZipName =
    'ayah-recitation-mishari-rashid-al-afasy-murattal-hafs-953.db.zip';
const String _recitationDbInnerName =
    'ayah-recitation-mishari-rashid-al-afasy-murattal-hafs-953.db';
const String _alafasyReciterId = 'mishari-alafasy';
const String _alafasyReciterName = 'مشاري راشد العفاسي';

/// Matches the `SSSAAA.mp3` filename convention `audio_url` uses (e.g.
/// `.../alafasy/002061.mp3` = surah 2, ayah 61) — used in `_buildAudio` as
/// an independent cross-check of the global-to-local ayah_number
/// conversion, since the filename's own embedded ayah number was recorded
/// by QUL from the *real* per-surah ayah, unlike the source table's own
/// `ayah_number` column (see `audioModuleResourceManifestSeed`'s doc
/// comment in resource_manifest_seed.dart).
final RegExp _audioUrlAyahPattern = RegExp(r'(\d{3})(\d{3})\.mp3$');

/// The `tafsir_sources` registry rows. Not derived from any downloaded
/// file — each source's name/author is hardcoded here, same treatment as
/// the other small pieces of static metadata already in this script (e.g.
/// `_supportedLineTypes`).
const List<Map<String, Object?>> _tafsirSources = [
  {
    'source_id': 'tafsir-ibn-kathir-ar',
    'name': 'تفسير ابن كثير',
    'language': 'ar',
    'author': 'ابن كثير',
  },
  {
    'source_id': 'tafsir-saadi-ar',
    'name': 'تفسير السعدي',
    'language': 'ar',
    'author': 'عبد الرحمن بن ناصر السعدي',
  },
  {
    'source_id': 'tafsir-iraab-muyassar-ar',
    'name': 'الإعراب الميسر',
    'language': 'ar',
    // Author isn't attributed on the resource's own QUL page — left null
    // rather than invented.
    'author': null,
  },
];

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
    final File ibnKathirDb = _extractSingleEntry(
      zip: File('${rawDir.path}/$_ibnKathirZipName'),
      entryName: _ibnKathirDbInnerName,
      outDir: work,
    );
    final File saadiDb = _extractSingleEntry(
      zip: File('${rawDir.path}/$_saadiZipName'),
      entryName: _saadiDbInnerName,
      outDir: work,
    );
    final File iraabDb = _extractSingleEntry(
      zip: File('${rawDir.path}/$_iraabZipName'),
      entryName: _iraabDbInnerName,
      outDir: work,
    );
    final File wordRootDb = _extractSingleEntry(
      zip: File('${rawDir.path}/$_wordRootZipName'),
      entryName: _wordRootDbInnerName,
      outDir: work,
    );
    final File wordLemmaDb = _extractSingleEntry(
      zip: File('${rawDir.path}/$_wordLemmaZipName'),
      entryName: _wordLemmaDbInnerName,
      outDir: work,
    );
    final File wordStemDb = _extractSingleEntry(
      zip: File('${rawDir.path}/$_wordStemZipName'),
      entryName: _wordStemDbInnerName,
      outDir: work,
    );
    final File recitationDb = _extractSingleEntry(
      zip: File('${rawDir.path}/$_recitationZipName'),
      entryName: _recitationDbInnerName,
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
    final List<Map<String, dynamic>> ibnKathirRows = _querySqliteJson(
      ibnKathirDb.path,
      'SELECT ayah_key, group_ayah_key, from_ayah, to_ayah, text FROM tafsir;',
    );
    final List<Map<String, dynamic>> saadiRows = _querySqliteJson(
      saadiDb.path,
      'SELECT ayah_key, group_ayah_key, from_ayah, to_ayah, text FROM tafsir;',
    );
    final List<Map<String, dynamic>> iraabRows = _querySqliteJson(
      iraabDb.path,
      'SELECT ayah_key, group_ayah_key, from_ayah, to_ayah, text FROM tafsir;',
    );
    // Each of these joins the word-location junction table back to its
    // parent dictionary table to get the actual root/lemma/stem text in one
    // query, rather than carrying the id indirection into Dart.
    final List<Map<String, dynamic>> rootRows = _querySqliteJson(
      wordRootDb.path,
      'SELECT rw.word_location AS word_location, r.arabic_trilateral AS text '
      'FROM root_words rw JOIN roots r ON rw.root_id = r.id;',
    );
    final List<Map<String, dynamic>> lemmaRows = _querySqliteJson(
      wordLemmaDb.path,
      'SELECT lw.word_location AS word_location, l.text AS text '
      'FROM lemma_words lw JOIN lemmas l ON lw.lemma_id = l.id;',
    );
    final List<Map<String, dynamic>> stemRows = _querySqliteJson(
      wordStemDb.path,
      'SELECT sw.word_location AS word_location, s.text AS text '
      'FROM stem_words sw JOIN stems s ON sw.stem_id = s.id;',
    );
    // Ordered by (surah_number, ayah_number) so `_buildAudio` can convert
    // this resource's own global 1-6236 `ayah_number` into a per-surah
    // number purely by rank-within-surah — see the manifest seed's doc
    // comment for why the source's own `ayah_number` can't be used as-is.
    final List<Map<String, dynamic>> recitationRows = _querySqliteJson(
      recitationDb.path,
      'SELECT surah_number, ayah_number, audio_url, segments FROM verses '
      'ORDER BY surah_number, ayah_number;',
    );

    print(
      'Loaded ${wordRows.length} words, ${pageRows.length} mushaf lines, '
      '${surahNamesRaw.length} surah name entries, '
      '${ibnKathirRows.length} + ${saadiRows.length} + ${iraabRows.length} '
      'tafsir rows (Ibn Kathir / As-Saadi / Iraab Al-Muyassar), '
      '${rootRows.length} + ${lemmaRows.length} + ${stemRows.length} '
      'morphology word-location rows (root / lemma / stem), '
      '${recitationRows.length} recitation rows (Mishari Alafasy).',
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
    final Map<String, List<Map<String, Object?>>> tafsirEntriesBySource = {
      'tafsir-ibn-kathir-ar': _buildTafsirEntries(
        'tafsir-ibn-kathir-ar',
        ibnKathirRows,
      ),
      'tafsir-saadi-ar': _buildTafsirEntries('tafsir-saadi-ar', saadiRows),
      'tafsir-iraab-muyassar-ar': _buildTafsirEntries(
        'tafsir-iraab-muyassar-ar',
        iraabRows,
      ),
    };
    final List<Map<String, Object?>> morphology = _buildMorphology(
      words: words,
      rootRows: rootRows,
      lemmaRows: lemmaRows,
      stemRows: stemRows,
    );
    final _AudioBuildResult audio = _buildAudio(
      recitationRows: recitationRows,
      words: words,
      reciterId: _alafasyReciterId,
      reciterName: _alafasyReciterName,
    );

    print('Running integrity checks (spec §24)...');
    final List<String> failures = _runIntegrityChecks(
      surahs: surahs,
      ayahs: ayahs,
      words: words,
      mushafLines: mushafLines,
    );
    failures.addAll(
      _runTafsirIntegrityChecks(
        ayahs: ayahs,
        tafsirSources: _tafsirSources,
        tafsirEntriesBySource: tafsirEntriesBySource,
      ),
    );
    failures.addAll(
      _runMorphologyIntegrityChecks(
        words: words,
        rootRows: rootRows,
        lemmaRows: lemmaRows,
        stemRows: stemRows,
        morphology: morphology,
      ),
    );
    failures.addAll(
      _runAudioIntegrityChecks(
        ayahs: ayahs,
        words: words,
        audioAssets: audio.audioAssets,
        audioSegments: audio.audioSegments,
      ),
    );
    if (failures.isNotEmpty) {
      _fail(
        'Integrity checks failed (${failures.length}):\n'
        '${failures.map((f) => '  - $f').join('\n')}\n'
        'assets/database/quran.db was NOT written/updated.',
      );
    }
    print('All integrity checks passed.');
    // Not failures — genuine upstream data-shape facts about this
    // recitation's own segment timing, verified during ingestion (see
    // tool/resource_manifest_seed.dart's `audioModuleResourceManifestSeed`
    // doc comment) and reported here so they're visible on every run, not
    // just discovered once and forgotten.
    print(
      "${audio.ayahsWithMarkerSegment} ayahs include a segment for the "
      "ayah-end marker (the recitation's own verse-end pause); "
      '${audio.ayahsWithExtraSegment} ayahs (11:44, 20:94, 37:102) have one '
      'segment beyond even that (an upstream alignment quirk, kept as-is).',
    );

    final DateTime retrievedAt = DateTime(2026, 8, 30);
    final DateTime tafsirRetrievedAt = DateTime(2026, 9, 11);
    final DateTime morphologyRetrievedAt = DateTime(2026, 9, 13);
    final DateTime audioRetrievedAt = DateTime(2026, 9, 14);
    final List<Map<String, Object?>> manifestRows = [
      ...phase0ResourceManifestSeed.map(
        (ResourceManifestEntry e) =>
            e.copyWith(retrievedAt: retrievedAt).toMap(),
      ),
      ...tafsirModuleResourceManifestSeed.map(
        (ResourceManifestEntry e) =>
            e.copyWith(retrievedAt: tafsirRetrievedAt).toMap(),
      ),
      ...morphologyModuleResourceManifestSeed.map(
        (ResourceManifestEntry e) =>
            e.copyWith(retrievedAt: morphologyRetrievedAt).toMap(),
      ),
      ...audioModuleResourceManifestSeed.map(
        (ResourceManifestEntry e) =>
            e.copyWith(retrievedAt: audioRetrievedAt).toMap(),
      ),
    ];

    final List<Map<String, Object?>> allTafsirEntries = [
      for (final entries in tafsirEntriesBySource.values) ...entries,
    ];

    print('Building SQL script...');
    final String sql = _buildSqlScript(
      surahs: surahs,
      ayahs: ayahs,
      words: words,
      mushafLines: mushafLines,
      tafsirSources: _tafsirSources,
      tafsirEntries: allTafsirEntries,
      morphology: morphology,
      audioAssets: audio.audioAssets,
      audioSegments: audio.audioSegments,
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
      expectedTafsirSources: _tafsirSources.length,
      expectedTafsirEntries: allTafsirEntries.length,
      expectedMorphology: morphology.length,
      expectedAudioAssets: audio.audioAssets.length,
      expectedAudioSegments: audio.audioSegments.length,
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

/// The qpc-v2 script resource stores the ayah-end ornament (the circled
/// ayah number every ayah ends with) as one extra "word" row per ayah,
/// always the highest `word` position in that ayah — confirmed by
/// cross-checking against the independently-sourced word-root/word-lemma/
/// word-stem resources (Prompt 12, spec §12), whose own word numbering
/// stops one position earlier for the same ayah in the overwhelming
/// majority of cases, and by an independent sanity total: 83668 words -
/// 6236 ayahs (one marker each) = 77432, matching the Quran's widely-cited
/// ~77,430 total word count. A real Mushaf-rendering requirement (rule
/// #2 — the line must show it) but not a real Quran word, so it's tagged
/// `word_type: 'end_marker'` here, once, rather than leaving every
/// word-level feature (e.g. Morphology) to re-derive "is this the last
/// position" itself.
List<Map<String, Object?>> _buildWords(List<Map<String, dynamic>> wordRows) {
  final Map<String, int> maxPositionByAyah = {};
  for (final w in wordRows) {
    final String ayahKey = '${w['surah']}:${w['ayah']}';
    final int position = w['word'] as int;
    final int? current = maxPositionByAyah[ayahKey];
    if (current == null || position > current) {
      maxPositionByAyah[ayahKey] = position;
    }
  }

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
          'word_type': (w['word'] as int) ==
                  maxPositionByAyah['${w['surah']}:${w['ayah']}']
              ? 'end_marker'
              : 'word',
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

String? _blankToNull(String? s) => (s == null || s.isEmpty) ? null : s;

/// Transforms one tafsir source's raw `tafsir` rows (schema verified by
/// hand against all 3 downloaded files: `tafsir(ayah_key, group_ayah_key,
/// from_ayah, to_ayah, ayah_keys, text)`) into `tafsir_entries` rows.
///
/// The source's own `group_ayah_key`/`from_ayah`/`to_ayah`/`text` columns
/// hold the real range and text only on a group's owning ayah; every other
/// member ayah in that group has those 4 fields blank and `group_ayah_key`
/// pointing back at the owner. This resolves the range once per group so
/// every output row (owner and members alike) carries
/// `group_ayah_start`/`group_ayah_end`, while `content` is populated only
/// on the owner (spec §11: "preserve group references" — not flattened
/// away by duplicating the text onto every member row).
List<Map<String, Object?>> _buildTafsirEntries(
  String sourceId,
  List<Map<String, dynamic>> rows,
) {
  final Map<String, String> startByGroup = {};
  final Map<String, String> endByGroup = {};
  for (final r in rows) {
    final String ayahKey = r['ayah_key'] as String;
    final String groupId =
        _blankToNull(r['group_ayah_key'] as String?) ?? ayahKey;
    final String? from = _blankToNull(r['from_ayah'] as String?);
    final String? to = _blankToNull(r['to_ayah'] as String?);
    if (from != null && to != null) {
      startByGroup[groupId] = from;
      endByGroup[groupId] = to;
    }
  }

  final List<Map<String, Object?>> result = [];
  for (final r in rows) {
    final String ayahKey = r['ayah_key'] as String;
    final List<String> parts = ayahKey.split(':');
    final String groupId =
        _blankToNull(r['group_ayah_key'] as String?) ?? ayahKey;
    final String? start = startByGroup[groupId];
    final String? end = endByGroup[groupId];
    if (start == null || end == null) {
      _fail(
        'Tafsir source "$sourceId": group "$groupId" (member ayah '
        '$ayahKey) has no owning row with a populated range.',
      );
    }
    result.add({
      'source_id': sourceId,
      'surah_id': int.parse(parts[0]),
      'ayah_number': int.parse(parts[1]),
      'ayah_key': ayahKey,
      'group_id': groupId,
      'group_ayah_start': start,
      'group_ayah_end': end,
      // Unmodified commentary text from the source, verbatim (still no
      // transformation, same spirit as rule #1, even though this isn't
      // Quran script) — blank means "not the group owner", per above.
      'content': _blankToNull(r['text'] as String?),
    });
  }
  result.sort((a, b) {
    final int s = (a['surah_id'] as int).compareTo(b['surah_id'] as int);
    if (s != 0) return s;
    return (a['ayah_number'] as int).compareTo(b['ayah_number'] as int);
  });
  return result;
}

/// Builds one `morphology` row per `words` row (schema.dart's `morphology`
/// table FKs onto `words` by `(surah_id, ayah_number, word_position)`, so
/// every word gets a row here — not just words that happen to have a
/// root/lemma/stem). `rootRows`/`lemmaRows`/`stemRows` are each
/// `{word_location, text}` pairs already joined back to their dictionary
/// table (see the 3 `_querySqliteJson` calls in `main`); `word_location`
/// uses the exact same `surah:ayah:word` format as `words.word_key`
/// (verified directly against both source files), so no reformatting is
/// needed to key the lookup.
///
/// A word with no row in one of the 3 maps (e.g. most particles have no
/// root) gets `null` for that column — a real linguistic fact, not a gap
/// to paper over (CLAUDE.md rule #1's spirit: never invent data).
List<Map<String, Object?>> _buildMorphology({
  required List<Map<String, Object?>> words,
  required List<Map<String, dynamic>> rootRows,
  required List<Map<String, dynamic>> lemmaRows,
  required List<Map<String, dynamic>> stemRows,
}) {
  Map<String, String> byLocation(List<Map<String, dynamic>> rows) => {
    for (final r in rows) r['word_location'] as String: r['text'] as String,
  };
  final Map<String, String> rootByLocation = byLocation(rootRows);
  final Map<String, String> lemmaByLocation = byLocation(lemmaRows);
  final Map<String, String> stemByLocation = byLocation(stemRows);

  return words.map((w) {
    final String wordKey = w['word_key'] as String;
    return {
      'surah_id': w['surah_id'] as int,
      'ayah_number': w['ayah_number'] as int,
      'word_position': w['word_position'] as int,
      'word_key': wordKey,
      'root': rootByLocation[wordKey],
      'lemma': lemmaByLocation[wordKey],
      'stem': stemByLocation[wordKey],
      // No POS/grammar-tag resource available alongside these on QUL
      // (spec §12.2 "(when available)") — left null, not derived from
      // anything else (spec §13's own warning against mislabeling a POS
      // tag as grammar analysis applies here too, in spirit).
      'part_of_speech': null,
      'grammar_tags': null,
    };
  }).toList();
}

/// [_buildAudio]'s result: `audio_assets` (one row per ayah) and
/// `audio_segments` (one row per word-timing entry) rows, plus two
/// informational counts (not integrity failures — see
/// tool/resource_manifest_seed.dart's `audioModuleResourceManifestSeed`
/// doc comment for what they mean).
class _AudioBuildResult {
  final List<Map<String, Object?>> audioAssets;
  final List<Map<String, Object?>> audioSegments;
  final int ayahsWithMarkerSegment;
  final int ayahsWithExtraSegment;

  const _AudioBuildResult({
    required this.audioAssets,
    required this.audioSegments,
    required this.ayahsWithMarkerSegment,
    required this.ayahsWithExtraSegment,
  });
}

/// Builds `audio_assets`/`audio_segments` rows (Prompt 13, spec §14) from
/// the single downloaded recitation resource. [recitationRows] is
/// `{surah_number, ayah_number, audio_url, segments}` straight from the
/// source `verses` table, still carrying that resource's own *global*
/// 1-6236 `ayah_number` (see the manifest seed's doc comment) — converted
/// here to the app's per-surah `ayah_number` by rank-within-surah, since
/// [recitationRows] is already ordered `(surah_number, ayah_number)` by the
/// query that produced it.
///
/// `segments` (a JSON string column) decodes to a list of
/// `[array_index, word_position, start_ms, end_ms]` — `word_position` is
/// matched against [words]' own `word_key` to resolve `audio_segments
/// .word_key`, left `null` when it doesn't resolve to a real ('word', not
/// 'end_marker') word — which happens for the two upstream anomalies the
/// manifest doc comment documents (a marker-only segment, or the 3-ayah
/// one-segment-too-many quirk), rather than inventing a word for it.
_AudioBuildResult _buildAudio({
  required List<Map<String, dynamic>> recitationRows,
  required List<Map<String, Object?>> words,
  required String reciterId,
  required String reciterName,
}) {
  final Map<int, List<Map<String, dynamic>>> rowsBySurah = {};
  for (final r in recitationRows) {
    (rowsBySurah[r['surah_number'] as int] ??= []).add(r);
  }

  final Map<String, String> wordTypeByKey = {
    for (final w in words) w['word_key'] as String: w['word_type'] as String,
  };

  final List<Map<String, Object?>> audioAssets = [];
  final List<Map<String, Object?>> audioSegments = [];
  int ayahsWithMarkerSegment = 0;
  int ayahsWithExtraSegment = 0;

  final List<int> surahIdsSorted = rowsBySurah.keys.toList()..sort();
  for (final surahId in surahIdsSorted) {
    final List<Map<String, dynamic>> rows = rowsBySurah[surahId]!;
    for (var i = 0; i < rows.length; i++) {
      final int localAyahNumber = i + 1;
      final Map<String, dynamic> row = rows[i];
      final String ayahKey = '$surahId:$localAyahNumber';
      final String audioId = '$reciterId:$ayahKey';
      final String audioUrl = row['audio_url'] as String;

      // Independent cross-check of the global-to-local conversion above:
      // the audio_url filename itself encodes the real surah/ayah (verified
      // by hand for a few rows, then here for all 6236) — if the rank-
      // within-surah conversion were ever wrong, this catches it instead
      // of silently mislabeling every audio file after the first mistake.
      final RegExpMatch? urlMatch = _audioUrlAyahPattern.firstMatch(audioUrl);
      if (urlMatch == null) {
        _fail(
          'Recitation audio_url "$audioUrl" does not match the expected '
          '.../SSSAAA.mp3 filename pattern.',
        );
      }
      final int urlSurah = int.parse(urlMatch.group(1)!);
      final int urlAyah = int.parse(urlMatch.group(2)!);
      if (urlSurah != surahId || urlAyah != localAyahNumber) {
        _fail(
          'Recitation ayah-numbering mismatch: computed local ayah '
          '$surahId:$localAyahNumber from rank-within-surah, but audio_url '
          '"$audioUrl" encodes $urlSurah:$urlAyah.',
        );
      }

      final List<dynamic> segmentsRaw =
          jsonDecode(row['segments'] as String) as List<dynamic>;

      int maxEndMs = 0;
      bool sawMarkerSegment = false;
      bool sawExtraSegment = false;
      for (var arrayIndex = 0; arrayIndex < segmentsRaw.length; arrayIndex++) {
        final List<dynamic> s = segmentsRaw[arrayIndex] as List<dynamic>;
        final int wordPosition = s[1] as int;
        final int startMs = s[2] as int;
        final int endMs = s[3] as int;
        if (endMs > maxEndMs) maxEndMs = endMs;

        final String segmentWordKey = '$surahId:$localAyahNumber:$wordPosition';
        final String? wordType = wordTypeByKey[segmentWordKey];
        if (wordType == 'end_marker') sawMarkerSegment = true;
        if (wordType == null) sawExtraSegment = true;

        audioSegments.add({
          'audio_id': audioId,
          // The segment array's own 0-based position, NOT `wordPosition` —
          // in ~1% of ayahs (61 of 6236, verified directly against the
          // downloaded file) the reciter audibly repeats a phrase mid-ayah,
          // so the *same* wordPosition appears twice in one ayah's segment
          // list (e.g. 2:68 says "قال إنه يقول" twice) with two different
          // timestamps. Using wordPosition as the key would collide on the
          // audio_segments PK; the array position is always unique and
          // preserves playback order, which is what actually matters for
          // driving the highlight forward through a repeat.
          'segment_index': arrayIndex,
          'word_key': wordType == 'word' ? segmentWordKey : null,
          'ayah_key': ayahKey,
          'start_ms': startMs,
          'end_ms': endMs,
        });
      }
      if (sawMarkerSegment) ayahsWithMarkerSegment++;
      if (sawExtraSegment) ayahsWithExtraSegment++;

      audioAssets.add({
        'audio_id': audioId,
        'reciter_id': reciterId,
        'reciter_name': reciterName,
        'surah_id': surahId,
        'ayah_key': ayahKey,
        'file_path': audioUrl,
        'format': 'mp3',
        // The source's own `duration` column is empty for all 6236 rows
        // (verified directly against the downloaded file) — derived from
        // the last segment's own end_ms instead of left NULL. Only used
        // for display before the real audio loads; the audio player
        // itself reports the authoritative duration at playback time.
        'duration_ms': maxEndMs,
      });
    }
  }

  return _AudioBuildResult(
    audioAssets: audioAssets,
    audioSegments: audioSegments,
    ayahsWithMarkerSegment: ayahsWithMarkerSegment,
    ayahsWithExtraSegment: ayahsWithExtraSegment,
  );
}

/// Audio-specific checks from spec §24 ("every file/segment references a
/// valid reciter and ayah", "segment ranges are non-negative"), plus this
/// module's own word_key-resolution invariant.
List<String> _runAudioIntegrityChecks({
  required List<Map<String, Object?>> ayahs,
  required List<Map<String, Object?>> words,
  required List<Map<String, Object?>> audioAssets,
  required List<Map<String, Object?>> audioSegments,
}) {
  final List<String> failures = [];
  final Set<String> ayahKeys = ayahs
      .map((a) => a['ayah_key'] as String)
      .toSet();

  if (audioAssets.length != ayahs.length) {
    failures.add(
      'audio_assets row count (${audioAssets.length}) does not match ayahs '
      'row count (${ayahs.length}) — expected exactly one audio asset per '
      'ayah.',
    );
  }

  final Set<String> seenAyahKeys = {};
  final Set<String> seenAudioIds = {};
  for (final a in audioAssets) {
    final String ayahKey = a['ayah_key'] as String;
    final String audioId = a['audio_id'] as String;
    if (!seenAyahKeys.add(ayahKey)) {
      failures.add('Duplicate audio_assets row for ayah_key "$ayahKey".');
    }
    if (!seenAudioIds.add(audioId)) {
      failures.add('Duplicate audio_id "$audioId".');
    }
    if (!ayahKeys.contains(ayahKey)) {
      failures.add(
        'audio_assets row references unknown ayah_key "$ayahKey".',
      );
    }
    final String filePath = a['file_path'] as String;
    if (!filePath.startsWith('https://') || !filePath.endsWith('.mp3')) {
      failures.add(
        'audio_assets row "$audioId" has an unexpected file_path (not an '
        'https .mp3 URL): "$filePath".',
      );
    }
  }

  final Map<String, String> wordTypeByKey = {
    for (final w in words) w['word_key'] as String: w['word_type'] as String,
  };
  for (final s in audioSegments) {
    final int startMs = s['start_ms'] as int;
    final int endMs = s['end_ms'] as int;
    if (startMs < 0 || endMs < 0 || startMs > endMs) {
      failures.add(
        'audio_segments row (audio_id "${s['audio_id']}", segment_index '
        '${s['segment_index']}) has an invalid time range: $startMs..'
        '$endMs.',
      );
    }
    final String? wordKey = s['word_key'] as String?;
    if (wordKey != null && wordTypeByKey[wordKey] != 'word') {
      failures.add(
        'audio_segments row references word_key "$wordKey" which is not a '
        'real word (word_type: ${wordTypeByKey[wordKey]}).',
      );
    }
    final String ayahKey = s['ayah_key'] as String;
    if (!ayahKeys.contains(ayahKey)) {
      failures.add(
        'audio_segments row references unknown ayah_key "$ayahKey".',
      );
    }
  }

  return failures;
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
  final Map<String, List<Map<String, Object?>>> wordRowsByAyah = {};
  for (final w in words) {
    final String key = '${w['surah_id']}:${w['ayah_number']}';
    (wordPositionsByAyah[key] ??= []).add(w['word_position'] as int);
    (wordRowsByAyah[key] ??= []).add(w);
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

  // `word_type`: exactly one 'end_marker' per ayah (the ayah-end ornament,
  // see `_buildWords`'s doc comment), and it must be that ayah's highest
  // word_position — never a real word wrongly tagged, never a real word
  // left untagged.
  wordRowsByAyah.forEach((ayahKey, rows) {
    final List<Map<String, Object?>> markers =
        rows.where((r) => r['word_type'] == 'end_marker').toList();
    if (markers.length != 1) {
      failures.add(
        "Ayah $ayahKey has ${markers.length} 'end_marker' word(s) "
        '(expected exactly 1).',
      );
    } else {
      final int markerPosition = markers.single['word_position'] as int;
      final int maxPosition =
          rows.map((r) => r['word_position'] as int).reduce((a, b) => a > b ? a : b);
      if (markerPosition != maxPosition) {
        failures.add(
          "Ayah $ayahKey's 'end_marker' is at position $markerPosition, "
          'but its highest word_position is $maxPosition.',
        );
      }
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

/// Regex for "contains at least one Arabic-script character" — a cheap
/// sanity check against wholesale mojibake (the exact Windows-encoding bug
/// class this pipeline already found and fixed once for Quran script text
/// — see the CLAUDE.md "Current phase" writeup). `_querySqliteJson` always
/// forces UTF-8 decoding already, so this isn't expected to ever fire; it
/// exists as a second, independent line of defense for tafsir content the
/// same way `_verifyWordBytesMatchSource` is for Quran script.
final RegExp _arabicScriptPattern = RegExp('[؀-ۿ]');

List<String> _runTafsirIntegrityChecks({
  required List<Map<String, Object?>> ayahs,
  required List<Map<String, Object?>> tafsirSources,
  required Map<String, List<Map<String, Object?>>> tafsirEntriesBySource,
}) {
  final List<String> failures = [];
  final Set<String> allAyahKeys = ayahs
      .map((a) => a['ayah_key'] as String)
      .toSet();
  final Set<String> sourceIds = tafsirSources
      .map((s) => s['source_id'] as String)
      .toSet();

  tafsirEntriesBySource.forEach((sourceId, entries) {
    if (!sourceIds.contains(sourceId)) {
      failures.add(
        'Tafsir entries reference unknown source_id "$sourceId" (no '
        'tafsir_sources row).',
      );
    }
    if (entries.length != allAyahKeys.length) {
      failures.add(
        'Tafsir source "$sourceId": ${entries.length} entries, expected '
        '${allAyahKeys.length} (one per ayah).',
      );
    }

    final Set<String> seenKeys = {};
    final Set<String> ownerKeysWithContent = {};
    int noContentCount = 0;
    final List<String> noArabicContentKeys = [];
    for (final e in entries) {
      final String ayahKey = e['ayah_key'] as String;
      if (!seenKeys.add(ayahKey)) {
        failures.add(
          'Tafsir source "$sourceId": duplicate ayah_key "$ayahKey".',
        );
      }
      if (!allAyahKeys.contains(ayahKey)) {
        failures.add(
          'Tafsir source "$sourceId": ayah_key "$ayahKey" has no matching '
          'ayahs row.',
        );
      }
      final String groupId = e['group_id'] as String;
      final String start = e['group_ayah_start'] as String;
      final String end = e['group_ayah_end'] as String;
      final String? content = e['content'] as String?;
      final bool isMultiAyahGroup = start != end;
      if (ayahKey == groupId) {
        // The group's owning row. Verified directly against all 3
        // downloaded sources: a *standalone* ayah (start == end, i.e. not
        // really grouped with anything) can legitimately have no content
        // at all — some sources (As-Saadi, 59 cases) genuinely skip
        // commentary on certain ayahs rather than export an empty string
        // as a placeholder. That's a real editorial gap, not a defect. A
        // *multi-ayah* group's owner having no content would mean the
        // whole group's tafsir is unrecoverable, which is a real defect.
        if (content == null) {
          noContentCount++;
          if (isMultiAyahGroup) {
            failures.add(
              'Tafsir source "$sourceId": multi-ayah group "$groupId" '
              '($start..$end) has no content on its owning row.',
            );
          }
        } else {
          if (!_arabicScriptPattern.hasMatch(content)) {
            // Verified directly against the source (not a transform bug):
            // a handful of As-Saadi rows (2:52, 2:53, 2:103, 23:38) hold a
            // single placeholder symbol ("×", "*", "-") instead of Arabic
            // text in the export itself. `_querySqliteJson` already forces
            // UTF-8 decoding for every query, so this isn't the historical
            // mojibake bug (CLAUDE.md "Current phase") recurring — it's
            // genuine upstream content, kept verbatim rather than treated
            // as a failure (rule #1's spirit: never invent/alter, not even
            // to "fix" something that looks odd).
            noArabicContentKeys.add('$sourceId:$ayahKey');
          }
          ownerKeysWithContent.add(groupId);
        }
      } else if (content != null) {
        failures.add(
          'Tafsir source "$sourceId": non-owner ayah "$ayahKey" (group '
          '"$groupId") unexpectedly has its own content.',
        );
      }
      if (!allAyahKeys.contains(start) || !allAyahKeys.contains(end)) {
        failures.add(
          'Tafsir source "$sourceId": group "$groupId" range ($start..'
          '$end) references an ayah that does not exist.',
        );
      }
    }
    // Every group_id used above must resolve to some row that actually
    // exists in this source (a real structural defect if not) — content
    // being present on that row is verified separately above, only for
    // multi-ayah groups.
    for (final e in entries) {
      final String groupId = e['group_id'] as String;
      if (!seenKeys.contains(groupId)) {
        failures.add(
          'Tafsir source "$sourceId": group "$groupId" has no owning row '
          'at all (dangling group reference).',
        );
      }
    }
    if (noContentCount > 0) {
      print(
        '  Note: tafsir source "$sourceId" has $noContentCount ayah(s) '
        'with no independent commentary in the source export (all '
        'standalone, none part of a multi-ayah group) — recorded as-is, '
        'not invented.',
      );
    }
    if (noArabicContentKeys.isNotEmpty) {
      print(
        '  Note: tafsir source "$sourceId" has ${noArabicContentKeys.length} '
        'entries whose content has no Arabic-script characters '
        '(${noArabicContentKeys.join(", ")}) — verified against the source '
        'file directly, genuine upstream content, not a transform bug.',
      );
    }
    final Set<String> missing = allAyahKeys.difference(seenKeys);
    if (missing.isNotEmpty) {
      failures.add(
        'Tafsir source "$sourceId" is missing entries for: '
        '${missing.take(5).join(", ")}'
        '${missing.length > 5 ? " (+${missing.length - 5} more)" : ""}.',
      );
    }
  });

  return failures;
}

/// Cheap sanity check that a root/lemma/stem's own text actually looks like
/// Arabic script — same class of second-line-of-defense check as
/// `_arabicScriptPattern` is for tafsir content, guarding against the same
/// encoding-mishandling bug class this pipeline already found and fixed
/// once (CLAUDE.md "Current phase"). `_querySqliteJson` already forces
/// UTF-8 decoding, so this isn't expected to ever fire.
List<String> _runMorphologyIntegrityChecks({
  required List<Map<String, Object?>> words,
  required List<Map<String, dynamic>> rootRows,
  required List<Map<String, dynamic>> lemmaRows,
  required List<Map<String, dynamic>> stemRows,
  required List<Map<String, Object?>> morphology,
}) {
  final List<String> failures = [];
  final Set<String> wordKeys = words.map((w) => w['word_key'] as String).toSet();

  if (morphology.length != words.length) {
    failures.add(
      'morphology row count (${morphology.length}) does not match words row '
      'count (${words.length}) — expected exactly one morphology row per '
      'word.',
    );
  }

  void checkSourceRows(String label, List<Map<String, dynamic>> rows) {
    final Set<String> seenLocations = {};
    for (final r in rows) {
      final String location = r['word_location'] as String;
      final String text = r['text'] as String;
      if (!seenLocations.add(location)) {
        failures.add(
          'Morphology source "$label": word_location "$location" appears '
          'more than once (expected at most one $label per word).',
        );
      }
      if (!wordKeys.contains(location)) {
        failures.add(
          'Morphology source "$label": word_location "$location" does not '
          'match any word_key in words.',
        );
      }
      if (!_arabicScriptPattern.hasMatch(text)) {
        failures.add(
          'Morphology source "$label": text for "$location" has no '
          'Arabic-script characters ("$text").',
        );
      }
    }
  }

  checkSourceRows('root', rootRows);
  checkSourceRows('lemma', lemmaRows);
  checkSourceRows('stem', stemRows);

  final Set<String> seenMorphologyKeys = {};
  for (final m in morphology) {
    final String wordKey = m['word_key'] as String;
    if (!seenMorphologyKeys.add(wordKey)) {
      failures.add('Duplicate morphology row for word_key "$wordKey".');
    }
  }

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
  required List<Map<String, Object?>> tafsirSources,
  required List<Map<String, Object?>> tafsirEntries,
  required List<Map<String, Object?>> morphology,
  required List<Map<String, Object?>> audioAssets,
  required List<Map<String, Object?>> audioSegments,
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
  for (final statement in additionalIndexStatements) {
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
  for (final row in tafsirSources) {
    sql.writeln(_insertStatement('tafsir_sources', row));
  }
  for (final row in tafsirEntries) {
    sql.writeln(_insertStatement('tafsir_entries', row));
  }
  for (final row in morphology) {
    sql.writeln(_insertStatement('morphology', row));
  }
  for (final row in audioAssets) {
    sql.writeln(_insertStatement('audio_assets', row));
  }
  for (final row in audioSegments) {
    sql.writeln(_insertStatement('audio_segments', row));
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
  required int expectedTafsirSources,
  required int expectedTafsirEntries,
  required int expectedMorphology,
  required int expectedAudioAssets,
  required int expectedAudioSegments,
  required int expectedManifestRows,
}) {
  final Map<String, int> expected = {
    'surahs': expectedSurahs,
    'ayahs': expectedAyahs,
    'words': expectedWords,
    'mushaf_lines': expectedMushafLines,
    'tafsir_sources': expectedTafsirSources,
    'tafsir_entries': expectedTafsirEntries,
    'morphology': expectedMorphology,
    'audio_assets': expectedAudioAssets,
    'audio_segments': expectedAudioSegments,
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
