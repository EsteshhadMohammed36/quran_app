// Diagnostic script (NOT part of tool/ingest_quran_data.dart's pipeline):
// cross-checks every one of the 604 pages in the shipped
// assets/database/quran.db's `mushaf_lines` table against quran.com's public
// API (mushaf=1, i.e. "QCF V2" - the exact same font/layout family this app
// renders with) to find any page whose word-to-line assignment diverges from
// the real printed Mushaf.
//
// Background (2026-09-19): the user reported Surah Al-Ikhlas' line breaks on
// page 604 didn't match a real Mushaf. Manually checking page 604 against
// quran.com's live API confirmed a real bug (Al-Ikhlas + Al-Falaq's line
// breaks were wrong), but pages 1 and 300 matched perfectly - so this is
// likely a handful of bad rows in the downloaded QUL resource
// (`qul-mushaf-layout-kfgqpc-v2-1421h`, raw_resources/qpc-v2-15-lines.db.zip)
// rather than the whole file being wrong. This script finds every affected
// page (not just 604) before any fix is applied, per the user's explicit
// ask: "عاوزة المصحف لاينز تبقي مطابقة تماما للمصحف الاصلي".
//
// Usage: dart run tool/audit_mushaf_lines.dart [--db=path] [--start=1] [--end=604]
//
// For every page, compares our `mushaf_lines` (line_type='ayah' rows only -
// surah_name/basmallah rows carry no independent per-ayah word content to
// diff) word-to-line assignment, keyed by (surah, ayah, word_position),
// against quran.com's `line_number` field for the same key. Any page with at
// least one differing key is written to
// tool/mushaf_line_audit_report.json - both a human-readable summary and,
// for each mismatching page, the *corrected* first_word_id/last_word_id
// ranges (computed from quran.com's line numbers, re-expressed using our own
// word_index scheme) so a follow-up fix can apply them directly instead of
// hand-deriving ranges again.
//
// Deliberately a read-only diagnostic: it never touches quran.db. Network
// calls are rate-limited (250ms between requests) to avoid hammering
// quran.com's public API - a full 604-page run takes several minutes.

import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  final Map<String, String> flags = {
    for (final a in args)
      if (a.startsWith('--') && a.contains('='))
        a.substring(2, a.indexOf('=')): a.substring(a.indexOf('=') + 1),
  };
  final String dbPath = flags['db'] ?? 'assets/database/quran.db';
  final int startPage = int.parse(flags['start'] ?? '1');
  final int endPage = int.parse(flags['end'] ?? '604');

  if (!File(dbPath).existsSync()) {
    stderr.writeln('Database not found at $dbPath');
    exit(1);
  }

  final client = HttpClient();
  final List<Map<String, dynamic>> pageReports = [];
  int pagesChecked = 0;
  int pagesMismatched = 0;

  for (int page = startPage; page <= endPage; page++) {
    pagesChecked++;
    final ourLines = _queryOurAyahLines(dbPath, page);
    if (ourLines.isEmpty) {
      stdout.writeln('[page $page] no ayah-type mushaf_lines rows - skipping');
      continue;
    }

    // key: "surah:ayah:position" -> our line_number
    final Map<String, int> ourLineByWord = {};
    for (final line in ourLines) {
      final words = _queryWordsInRange(
        dbPath,
        line['first_word_id'] as int,
        line['last_word_id'] as int,
      );
      for (final w in words) {
        final key = '${w['surah_id']}:${w['ayah_number']}:${w['word_position']}';
        ourLineByWord[key] = line['line_number'] as int;
      }
    }

    Map<String, int>? apiLineByWord;
    for (int attempt = 1; attempt <= 3; attempt++) {
      try {
        apiLineByWord = await _fetchApiLineByWord(client, page);
        break;
      } catch (e) {
        stderr.writeln('[page $page] attempt $attempt failed: $e');
        await Future.delayed(const Duration(milliseconds: 800));
      }
    }
    if (apiLineByWord == null) {
      stderr.writeln('[page $page] giving up after 3 attempts - SKIPPED');
      continue;
    }

    final List<Map<String, dynamic>> mismatches = [];
    for (final key in ourLineByWord.keys) {
      final ours = ourLineByWord[key];
      final api = apiLineByWord[key];
      if (api == null) continue; // basmallah/other keys the API scopes differently
      if (ours != api) {
        mismatches.add({'word': key, 'ourLine': ours, 'apiLine': api});
      }
    }

    if (mismatches.isNotEmpty) {
      pagesMismatched++;
      // Derive corrected first_word_id/last_word_id per our own line_number
      // grid, using the API's line assignment applied to our word_index
      // scheme (so the fix can be expressed in terms this app already uses).
      final Map<int, List<int>> apiWordIndexesByLine = {};
      for (final line in ourLines) {
        final words = _queryWordsInRange(
          dbPath,
          line['first_word_id'] as int,
          line['last_word_id'] as int,
        );
        for (final w in words) {
          final key =
              '${w['surah_id']}:${w['ayah_number']}:${w['word_position']}';
          final apiLine = apiLineByWord[key];
          if (apiLine == null) continue;
          apiWordIndexesByLine
              .putIfAbsent(apiLine, () => [])
              .add(w['word_index'] as int);
        }
      }
      final corrected = [
        for (final entry in apiWordIndexesByLine.entries)
          {
            'line_number': entry.key,
            'first_word_id': entry.value.reduce((a, b) => a < b ? a : b),
            'last_word_id': entry.value.reduce((a, b) => a > b ? a : b),
          },
      ]..sort((a, b) => (a['line_number'] as int).compareTo(b['line_number'] as int));

      pageReports.add({
        'page': page,
        'mismatchCount': mismatches.length,
        'mismatches': mismatches,
        'ourLines': ourLines,
        'correctedLines': corrected,
      });
      stdout.writeln('[page $page] MISMATCH: ${mismatches.length} word(s) differ');
    } else {
      stdout.writeln('[page $page] OK');
    }

    await Future.delayed(const Duration(milliseconds: 250));
  }

  client.close();

  final report = {
    'generatedAt': DateTime.now().toIso8601String(),
    'source': 'https://api.quran.com/api/v4/verses/by_page/{page}?words=true&word_fields=line_number&mushaf=1',
    'pagesChecked': pagesChecked,
    'pagesMismatched': pagesMismatched,
    'mismatchedPages': pageReports,
  };
  final outFile = File('tool/mushaf_line_audit_report.json');
  outFile.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(report));

  stdout.writeln('');
  stdout.writeln('=== DONE ===');
  stdout.writeln('Pages checked: $pagesChecked');
  stdout.writeln('Pages with mismatches: $pagesMismatched');
  stdout.writeln('Report written to ${outFile.path}');
}

List<Map<String, dynamic>> _queryOurAyahLines(String dbPath, int page) {
  return _querySqliteJson(
    dbPath,
    "SELECT line_number, first_word_id, last_word_id FROM mushaf_lines "
    "WHERE page_number = $page AND line_type = 'ayah' ORDER BY line_number ASC;",
  );
}

List<Map<String, dynamic>> _queryWordsInRange(String dbPath, int first, int last) {
  return _querySqliteJson(
    dbPath,
    'SELECT word_index, surah_id, ayah_number, word_position FROM words '
    'WHERE word_index BETWEEN $first AND $last ORDER BY word_index ASC;',
  );
}

List<Map<String, dynamic>> _querySqliteJson(String dbPath, String sql) {
  final ProcessResult result = Process.runSync(
    'sqlite3',
    [dbPath, '-json', sql],
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
  );
  if (result.exitCode != 0) {
    throw StateError('sqlite3 query failed:\n$sql\n${result.stderr}');
  }
  final String out = (result.stdout as String).trim();
  if (out.isEmpty) return [];
  return (jsonDecode(out) as List).cast<Map<String, dynamic>>();
}

/// Fetches quran.com's per-word line numbers for [page] (mushaf=1, QCF V2),
/// keyed by "surah:ayah:position" to match our own word identity scheme
/// (global word_index doesn't exist on their side, but surah/ayah/position
/// does on both).
Future<Map<String, int>> _fetchApiLineByWord(HttpClient client, int page) async {
  final uri = Uri.parse(
    'https://api.quran.com/api/v4/verses/by_page/$page'
    '?words=true&word_fields=line_number&fields=text_uthmani&mushaf=1',
  );
  final request = await client.getUrl(uri).timeout(const Duration(seconds: 15));
  final response = await request.close().timeout(const Duration(seconds: 15));
  if (response.statusCode != 200) {
    throw StateError('HTTP ${response.statusCode} for $uri');
  }
  final body = await response.transform(utf8.decoder).join();
  final json = jsonDecode(body) as Map<String, dynamic>;
  final verses = json['verses'] as List;
  final Map<String, int> result = {};
  for (final v in verses) {
    final verse = v as Map<String, dynamic>;
    final parts = (verse['verse_key'] as String).split(':');
    final surah = parts[0];
    final ayah = parts[1];
    final words = verse['words'] as List;
    for (final w in words) {
      final word = w as Map<String, dynamic>;
      final charType = word['char_type_name'];
      // "end" = the ayah-number ornament glyph, matches our word_position
      // continuing past the real words (word_type='end_marker'); "word" is
      // a normal word. Position is 1-based on both sides.
      if (charType != 'word' && charType != 'end') continue;
      final position = word['position'] as int;
      final lineNumber = word['line_number'] as int;
      result['$surah:$ayah:$position'] = lineNumber;
    }
  }
  return result;
}
