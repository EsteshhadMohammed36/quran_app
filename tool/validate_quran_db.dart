// ignore_for_file: avoid_print
//
// Automated Validation Suite (spec §24) — Prompt 16.
//
// Distinct from (and complementary to) tool/ingest_quran_data.dart's own
// `_runIntegrityChecks`/`_runTafsirIntegrityChecks`/
// `_runMorphologyIntegrityChecks`/`_runAudioIntegrityChecks`: those already
// implement every spec §24 bullet, but only run against the *intermediate*
// in-memory rows built from `raw_resources/` (git-ignored) during a full
// re-ingestion — they can't be run on their own, and they validate the data
// *before* it's written to SQL, not the actual bytes that ship in the app.
//
// This script instead runs the same spec §24 checks directly, via SQL,
// against the real shipped database file (`assets/database/quran.db`,
// checked into git — unlike `raw_resources/`). That makes it a fast,
// standalone, repeatable gate anyone can run at any time — no downloaded
// resources required — to confirm the checked-in `quran.db` itself is
// still sound (e.g. after a manual edit, a partial re-ingestion, or simply
// as a CI-style regression check before a release).
//
// Usage: dart run tool/validate_quran_db.dart [--db=path]
//   (defaults to assets/database/quran.db)
//
// Requires the `sqlite3` CLI on PATH (same as tool/ingest_quran_data.dart —
// zero native/FFI Dart dependencies).
//
// Read-only: never writes to the database.

library;

import 'dart:convert';
import 'dart:io';

void main(List<String> args) {
  final Map<String, String> flags = {
    for (final a in args)
      if (a.startsWith('--') && a.contains('='))
        a.substring(2, a.indexOf('=')): a.substring(a.indexOf('=') + 1),
  };
  final String dbPath = flags['db'] ?? 'assets/database/quran.db';

  if (!File(dbPath).existsSync()) {
    stderr.writeln('Database not found at $dbPath');
    exit(1);
  }

  print('Validating $dbPath against spec §24...\n');

  final List<_CheckResult> results = [
    ..._quranIntegrityChecks(dbPath),
    ..._mushafLayoutChecks(dbPath),
    ..._tafsirChecks(dbPath),
    ..._morphologyChecks(dbPath),
    ..._audioChecks(dbPath),
  ];

  final List<_CheckResult> failed = [];
  for (final result in results) {
    final String status = result.passed ? 'PASS' : 'FAIL';
    print('[$status] ${result.name}');
    if (!result.passed) {
      for (final detail in result.details) {
        print('       $detail');
      }
      failed.add(result);
    }
  }

  print('\n${results.length} checks run, ${failed.length} failed.');
  if (failed.isNotEmpty) {
    exit(1);
  }
  print('All spec §24 checks passed.');
}

class _CheckResult {
  final String name;
  final bool passed;
  final List<String> details;

  _CheckResult.pass(this.name) : passed = true, details = const [];

  _CheckResult.fail(this.name, this.details) : passed = false;
}

/// One `SELECT COUNT(*) AS c FROM ...` query, returned as an int.
int _count(String dbPath, String sql) {
  final rows = _queryJson(dbPath, sql);
  return rows.first['c'] as int;
}

/// A count-based check: `sql` must return zero rows/zero count for the
/// check to pass. `describeRow` renders one offending row for the failure
/// detail list (capped at 5) when `sql` returns actual rows rather than a
/// bare count.
_CheckResult _expectZeroRows(
  String dbPath,
  String name,
  String sql, {
  String Function(Map<String, dynamic> row)? describeRow,
}) {
  final rows = _queryJson(dbPath, sql);
  if (rows.isEmpty) return _CheckResult.pass(name);
  final describe = describeRow ?? (row) => row.toString();
  return _CheckResult.fail(name, [
    '${rows.length} offending row(s), e.g.:',
    ...rows.take(5).map(describe),
  ]);
}

List<_CheckResult> _quranIntegrityChecks(String dbPath) {
  final results = <_CheckResult>[];

  // 114 surahs present.
  final int surahCount = _count(dbPath, 'SELECT COUNT(*) AS c FROM surahs;');
  final int distinctValidIds = _count(
    dbPath,
    'SELECT COUNT(*) AS c FROM surahs WHERE surah_id BETWEEN 1 AND 114;',
  );
  results.add(
    surahCount == 114 && distinctValidIds == 114
        ? _CheckResult.pass('114 surahs present')
        : _CheckResult.fail('114 surahs present', [
            'found $surahCount surahs row(s), $distinctValidIds with '
                'surah_id in 1..114.',
          ]),
  );

  // Expected ayah counts per surah (surahs.ayah_count vs actual ayahs rows).
  results.add(
    _expectZeroRows(
      dbPath,
      'Expected ayah counts per surah',
      '''
      SELECT s.surah_id, s.ayah_count AS expected, COUNT(a.ayah_number) AS actual
      FROM surahs s
      LEFT JOIN ayahs a ON a.surah_id = s.surah_id
      GROUP BY s.surah_id
      HAVING expected <> actual;
      ''',
      describeRow: (r) =>
          'surah ${r['surah_id']}: expected ${r['expected']}, found ${r['actual']}',
    ),
  );

  // No duplicate (surah_id, ayah_number).
  results.add(
    _expectZeroRows(
      dbPath,
      'No duplicate (surah_id, ayah_number)',
      '''
      SELECT surah_id, ayah_number, COUNT(*) AS c
      FROM ayahs
      GROUP BY surah_id, ayah_number
      HAVING c > 1;
      ''',
      describeRow: (r) => '${r['surah_id']}:${r['ayah_number']} (${r['c']}x)',
    ),
  );

  // No orphan words (every word's (surah_id, ayah_number) must have an
  // ayahs row).
  results.add(
    _expectZeroRows(
      dbPath,
      'No orphan words',
      '''
      SELECT w.surah_id, w.ayah_number, COUNT(*) AS c
      FROM words w
      LEFT JOIN ayahs a
        ON a.surah_id = w.surah_id AND a.ayah_number = w.ayah_number
      WHERE a.surah_id IS NULL
      GROUP BY w.surah_id, w.ayah_number;
      ''',
      describeRow: (r) => '${r['surah_id']}:${r['ayah_number']} (${r['c']} word row(s))',
    ),
  );

  // No invalid word positions: every ayah's word_position set must be
  // exactly 1..N with no gaps/duplicates. `words`' own primary key
  // (surah_id, ayah_number, word_position) already rules out duplicates, so
  // checking min == 1 and max == count is sufficient to prove contiguity.
  results.add(
    _expectZeroRows(
      dbPath,
      'No invalid word positions',
      '''
      SELECT surah_id, ayah_number, MIN(word_position) AS min_pos,
             MAX(word_position) AS max_pos, COUNT(*) AS c
      FROM words
      GROUP BY surah_id, ayah_number
      HAVING min_pos <> 1 OR max_pos <> c;
      ''',
      describeRow: (r) =>
          '${r['surah_id']}:${r['ayah_number']} positions '
          '${r['min_pos']}..${r['max_pos']} over ${r['c']} word(s)',
    ),
  );

  return results;
}

List<_CheckResult> _mushafLayoutChecks(String dbPath) {
  final results = <_CheckResult>[];

  // Page numbers within the installed layout's own range: no gaps between 1
  // and the layout's own MAX(page_number) — not a hardcoded 604, so this
  // stays correct if a different Mushaf Layout is ever installed.
  final rangeRows = _queryJson(
    dbPath,
    'SELECT MIN(page_number) AS min_p, MAX(page_number) AS max_p, '
    'COUNT(DISTINCT page_number) AS distinct_p FROM mushaf_lines;',
  );
  final minPage = rangeRows.first['min_p'] as int?;
  final maxPage = rangeRows.first['max_p'] as int?;
  final distinctPages = rangeRows.first['distinct_p'] as int?;
  final bool rangeOk =
      minPage == 1 && maxPage != null && distinctPages == maxPage;
  results.add(
    rangeOk
        ? _CheckResult.pass('Page numbers within layout range, no gaps')
        : _CheckResult.fail('Page numbers within layout range, no gaps', [
            'min=$minPage max=$maxPage distinct=$distinctPages '
                '(expected min=1 and distinct == max, i.e. no gaps).',
          ]),
  );

  // Line numbers unique per page (schema PK already enforces this at write
  // time; asserted directly here too since this suite validates the
  // shipped bytes, not the writer's own guarantees).
  results.add(
    _expectZeroRows(
      dbPath,
      'Line numbers unique per page',
      '''
      SELECT page_number, line_number, COUNT(*) AS c
      FROM mushaf_lines
      GROUP BY page_number, line_number
      HAVING c > 1;
      ''',
      describeRow: (r) => 'page ${r['page_number']} line ${r['line_number']} (${r['c']}x)',
    ),
  );

  // first_word_id <= last_word_id, for ayah lines only (the only line_type
  // that carries a word range).
  results.add(
    _expectZeroRows(
      dbPath,
      'first_word_id <= last_word_id',
      '''
      SELECT page_number, line_number, first_word_id, last_word_id
      FROM mushaf_lines
      WHERE line_type = 'ayah' AND first_word_id > last_word_id;
      ''',
      describeRow: (r) =>
          'page ${r['page_number']} line ${r['line_number']}: '
          '${r['first_word_id']} > ${r['last_word_id']}',
    ),
  );

  // All referenced words exist: an ayah line's first/last_word_id must both
  // be real words.word_index values.
  results.add(
    _expectZeroRows(
      dbPath,
      'All referenced words exist',
      '''
      SELECT page_number, line_number, first_word_id, last_word_id
      FROM mushaf_lines
      WHERE line_type = 'ayah'
        AND (first_word_id NOT IN (SELECT word_index FROM words)
             OR last_word_id NOT IN (SELECT word_index FROM words));
      ''',
      describeRow: (r) =>
          'page ${r['page_number']} line ${r['line_number']}: range '
          '${r['first_word_id']}..${r['last_word_id']}',
    ),
  );

  // All line_type values are supported (schema.dart: 'ayah' | 'surah_name'
  // | 'basmallah').
  results.add(
    _expectZeroRows(
      dbPath,
      'All line_type values are supported',
      '''
      SELECT DISTINCT line_type
      FROM mushaf_lines
      WHERE line_type NOT IN ('ayah', 'surah_name', 'basmallah');
      ''',
      describeRow: (r) => 'line_type="${r['line_type']}"',
    ),
  );

  // surah_name lines have a valid surah_number.
  results.add(
    _expectZeroRows(
      dbPath,
      'surah_name lines have valid surah_number',
      '''
      SELECT page_number, line_number, surah_number
      FROM mushaf_lines
      WHERE line_type = 'surah_name'
        AND (surah_number IS NULL
             OR surah_number NOT IN (SELECT surah_id FROM surahs));
      ''',
      describeRow: (r) =>
          'page ${r['page_number']} line ${r['line_number']}: '
          'surah_number=${r['surah_number']}',
    ),
  );

  return results;
}

List<_CheckResult> _tafsirChecks(String dbPath) {
  final results = <_CheckResult>[];

  // Source IDs unique (schema PK already enforces; asserted directly here
  // too, same reasoning as the mushaf_lines line-number check above).
  results.add(
    _expectZeroRows(
      dbPath,
      'Tafsir source IDs unique',
      '''
      SELECT source_id, COUNT(*) AS c
      FROM tafsir_sources
      GROUP BY source_id
      HAVING c > 1;
      ''',
      describeRow: (r) => '${r['source_id']} (${r['c']}x)',
    ),
  );

  // Every entry's own source_id must be a real tafsir_sources row.
  results.add(
    _expectZeroRows(
      dbPath,
      'Tafsir entries reference a valid source',
      '''
      SELECT DISTINCT source_id
      FROM tafsir_entries
      WHERE source_id NOT IN (SELECT source_id FROM tafsir_sources);
      ''',
      describeRow: (r) => 'unknown source_id "${r['source_id']}"',
    ),
  );

  // ayah/group references valid: ayah_key, group_ayah_start and
  // group_ayah_end must each resolve to a real ayahs row.
  results.add(
    _expectZeroRows(
      dbPath,
      'Tafsir ayah/group references valid',
      '''
      SELECT source_id, ayah_key, group_ayah_start, group_ayah_end
      FROM tafsir_entries
      WHERE ayah_key NOT IN (SELECT ayah_key FROM ayahs)
         OR group_ayah_start NOT IN (SELECT ayah_key FROM ayahs)
         OR group_ayah_end NOT IN (SELECT ayah_key FROM ayahs);
      ''',
      describeRow: (r) =>
          '${r['source_id']}:${r['ayah_key']} (group '
          '${r['group_ayah_start']}..${r['group_ayah_end']})',
    ),
  );

  // No broken group references: every row's group_id must resolve to some
  // row that actually exists *for that same source* (the group's owning
  // row — see schema.dart's tafsir_entries doc comment).
  results.add(
    _expectZeroRows(
      dbPath,
      'No broken tafsir group references',
      '''
      SELECT te.source_id, te.ayah_key, te.group_id
      FROM tafsir_entries te
      WHERE NOT EXISTS (
        SELECT 1 FROM tafsir_entries owner
        WHERE owner.source_id = te.source_id AND owner.ayah_key = te.group_id
      );
      ''',
      describeRow: (r) =>
          '${r['source_id']}:${r['ayah_key']} -> dangling group '
          '"${r['group_id']}"',
    ),
  );

  return results;
}

List<_CheckResult> _morphologyChecks(String dbPath) {
  return [
    _expectZeroRows(
      dbPath,
      'Every morphology row maps to a valid word key',
      '''
      SELECT word_key
      FROM morphology
      WHERE word_key NOT IN (SELECT word_key FROM words);
      ''',
      describeRow: (r) => 'unknown word_key "${r['word_key']}"',
    ),
  ];
}

List<_CheckResult> _audioChecks(String dbPath) {
  final results = <_CheckResult>[];

  // Every audio_assets row references a valid reciter (non-empty — there's
  // no separate reciters table; AudioRepository.getReciters() itself
  // derives the reciter list from DISTINCT reciter_id in this same table)
  // and, when set, a valid ayah.
  results.add(
    _expectZeroRows(
      dbPath,
      'audio_assets reference a valid reciter and ayah',
      '''
      SELECT audio_id, reciter_id, ayah_key
      FROM audio_assets
      WHERE reciter_id IS NULL OR TRIM(reciter_id) = ''
         OR (ayah_key IS NOT NULL AND ayah_key NOT IN (SELECT ayah_key FROM ayahs));
      ''',
      describeRow: (r) =>
          '${r['audio_id']}: reciter_id="${r['reciter_id']}" '
          'ayah_key="${r['ayah_key']}"',
    ),
  );

  // Every audio_segments row references a valid ayah and a real
  // audio_assets row (its own "valid reciter", transitively).
  results.add(
    _expectZeroRows(
      dbPath,
      'audio_segments reference a valid reciter (audio asset) and ayah',
      '''
      SELECT s.audio_id, s.segment_index, s.ayah_key
      FROM audio_segments s
      WHERE (s.ayah_key IS NOT NULL AND s.ayah_key NOT IN (SELECT ayah_key FROM ayahs))
         OR s.audio_id NOT IN (SELECT audio_id FROM audio_assets);
      ''',
      describeRow: (r) =>
          '${r['audio_id']}#${r['segment_index']}: ayah_key="${r['ayah_key']}"',
    ),
  );

  // Segment ranges are non-negative (and start <= end).
  results.add(
    _expectZeroRows(
      dbPath,
      'audio_segments ranges are non-negative',
      '''
      SELECT audio_id, segment_index, start_ms, end_ms
      FROM audio_segments
      WHERE start_ms < 0 OR end_ms < 0 OR start_ms > end_ms;
      ''',
      describeRow: (r) =>
          '${r['audio_id']}#${r['segment_index']}: '
          '${r['start_ms']}..${r['end_ms']}',
    ),
  );

  return results;
}

List<Map<String, dynamic>> _queryJson(String dbPath, String sql) {
  // stdoutEncoding must be explicit: Process.runSync defaults to the
  // platform's system encoding (on Windows, an ANSI codepage, not UTF-8),
  // which would decode sqlite3's UTF-8 JSON output one byte at a time and
  // silently corrupt any multi-byte character in a failure detail (e.g. an
  // Arabic surah name) — same reasoning as tool/ingest_quran_data.dart's
  // identical `_querySqliteJson` helper.
  final ProcessResult result = Process.runSync(
    'sqlite3',
    [dbPath, '-json', sql],
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
  );
  if (result.exitCode != 0) {
    stderr.writeln('sqlite3 query failed on $dbPath:\n$sql\n${result.stderr}');
    exit(1);
  }
  final String out = (result.stdout as String).trim();
  if (out.isEmpty) return [];
  return (jsonDecode(out) as List).cast<Map<String, dynamic>>();
}
