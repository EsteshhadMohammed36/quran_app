// Extracts all 604 QPC V2 page fonts from raw_resources/QPC V2 Font.ttf.bz2
// (a zip archive despite the .bz2 name — 604 files, p1.ttf..p604.ttf) into
// assets/fonts/qpc_v2/, reads each font's REAL family name from its own
// 'name' table (spec §7: "use the exact family names included with the
// downloaded font package rather than hard-code a guessed family" — not
// assumed to follow the QCF2{page:03d} pattern, even though every page
// checked so far does), then regenerates:
//   - lib/features/quran_reader/presentation/qpc_v2_font_families.g.dart
//     (the page -> family map, generated, not hand-edited)
//   - the `fonts:` section of pubspec.yaml (604 QCF2xxx families, keeping
//     the existing QCF_SurahHeader_COLOR entry as-is)
//
// Run from the project root: dart run tool/extract_qpc_v2_fonts.dart
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';

const String _zipPath = 'raw_resources/QPC V2 Font.ttf.bz2';
const String _fontsOutDir = 'assets/fonts/qpc_v2';
const String _generatedDartPath =
    'lib/features/quran_reader/presentation/qpc_v2_font_families.g.dart';
const String _pubspecPath = 'pubspec.yaml';
const int _expectedPageCount = 604;

void main() {
  final zipBytes = File(_zipPath).readAsBytesSync();
  final archive = ZipDecoder().decodeBytes(zipBytes);

  final pageFileRegex = RegExp(r'^p(\d+)\.ttf$');
  final Map<int, String> familyByPage = {};

  Directory(_fontsOutDir).createSync(recursive: true);

  for (final entry in archive) {
    if (!entry.isFile) continue;
    final match = pageFileRegex.firstMatch(entry.name);
    if (match == null) {
      stderr.writeln('Skipping unexpected archive entry: ${entry.name}');
      continue;
    }
    final pageNumber = int.parse(match.group(1)!);
    final bytes = entry.content as List<int>;
    final fontBytes = Uint8List.fromList(bytes);

    final familyName = _readFamilyName(fontBytes);
    if (familyName == null) {
      throw StateError(
        'Could not read a family name from ${entry.name} (page $pageNumber) '
        "'name' table — refusing to guess one (spec §7).",
      );
    }
    familyByPage[pageNumber] = familyName;

    final outFile = File('$_fontsOutDir/p$pageNumber.ttf');
    outFile.writeAsBytesSync(fontBytes, flush: true);
  }

  // Integrity checks before trusting this data to generate app code.
  if (familyByPage.length != _expectedPageCount) {
    throw StateError(
      'Expected $_expectedPageCount page fonts, found ${familyByPage.length}.',
    );
  }
  for (int page = 1; page <= _expectedPageCount; page++) {
    if (!familyByPage.containsKey(page)) {
      throw StateError('Missing font for page $page.');
    }
  }
  final uniqueFamilies = familyByPage.values.toSet();
  if (uniqueFamilies.length != _expectedPageCount) {
    throw StateError(
      'Expected $_expectedPageCount unique family names, found '
      '${uniqueFamilies.length} — some pages share a family name.',
    );
  }

  _writeGeneratedDartFile(familyByPage);
  _rewritePubspecFontsSection(familyByPage);

  stdout.writeln(
    'Extracted ${familyByPage.length} fonts to $_fontsOutDir, '
    'regenerated $_generatedDartPath and the fonts: section of $_pubspecPath.',
  );
}

/// Reads the sfnt 'name' table and returns the Font Family name (nameID 1).
/// Prefers the Windows/Unicode BMP/en-US record (platformID 3, encodingID
/// 1, languageID 0x409) since that's what every page checked so far uses;
/// falls back to any platformID 3 record, then any record at all, rather
/// than assuming a pattern.
String? _readFamilyName(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  final numTables = data.getUint16(4);

  int? nameTableOffset;
  for (int i = 0; i < numTables; i++) {
    final recordOffset = 12 + i * 16;
    final tag = String.fromCharCodes(
      bytes.sublist(recordOffset, recordOffset + 4),
    );
    if (tag == 'name') {
      nameTableOffset = data.getUint32(recordOffset + 8);
      break;
    }
  }
  if (nameTableOffset == null) return null;

  final count = data.getUint16(nameTableOffset + 2);
  final stringAreaOffset = nameTableOffset + data.getUint16(nameTableOffset + 4);

  String? preferred;
  String? anyWindows;
  String? any;

  for (int i = 0; i < count; i++) {
    final recordOffset = nameTableOffset + 6 + i * 12;
    final platformId = data.getUint16(recordOffset);
    final encodingId = data.getUint16(recordOffset + 2);
    final languageId = data.getUint16(recordOffset + 4);
    final nameId = data.getUint16(recordOffset + 6);
    final length = data.getUint16(recordOffset + 8);
    final offset = data.getUint16(recordOffset + 10);
    if (nameId != 1) continue; // Font Family name only.

    final start = stringAreaOffset + offset;
    final raw = bytes.sublist(start, start + length);
    final value = _decodeNameBytes(raw, platformId);
    if (value == null || value.isEmpty) continue;

    any ??= value;
    if (platformId == 3) {
      anyWindows ??= value;
      if (encodingId == 1 && languageId == 0x0409) {
        preferred ??= value;
      }
    }
  }
  return preferred ?? anyWindows ?? any;
}

String? _decodeNameBytes(List<int> raw, int platformId) {
  if (platformId == 3 || platformId == 0) {
    // UTF-16BE (Windows / Unicode platforms).
    if (raw.length.isOdd) return null;
    final units = <int>[];
    for (int j = 0; j < raw.length; j += 2) {
      units.add((raw[j] << 8) | raw[j + 1]);
    }
    return String.fromCharCodes(units);
  }
  // Platform 1 (Macintosh) is effectively ASCII for these family names.
  return String.fromCharCodes(raw);
}

void _writeGeneratedDartFile(Map<int, String> familyByPage) {
  final buffer = StringBuffer()
    ..writeln(
      '// GENERATED FILE — do not hand-edit.\n'
      '// Produced by tool/extract_qpc_v2_fonts.dart from the family names\n'
      "// actually stored in each of the 604 QPC V2 page fonts' own 'name'\n"
      '// tables (spec §7) — not guessed from the QCF2{page:03d} pattern,\n'
      '// even though every page happens to follow it. Re-run the tool to\n'
      '// regenerate this file if raw_resources/QPC V2 Font.ttf.bz2 changes.\n',
    )
    ..writeln('const Map<int, String> generatedQpcV2FontFamilyByPage = {');
  for (int page = 1; page <= _expectedPageCount; page++) {
    buffer.writeln("  $page: '${familyByPage[page]}',");
  }
  buffer.writeln('};');

  File(_generatedDartPath).writeAsStringSync(buffer.toString());
}

void _rewritePubspecFontsSection(Map<int, String> familyByPage) {
  final original = File(_pubspecPath).readAsStringSync();
  // pubspec.yaml is CRLF on this project (Windows checkout) — match the
  // marker text itself, not an assumed line-ending, then find the real
  // newline (\r\n or \n) that follows it to locate the actual insert point.
  const startMarkerText = '  fonts:';
  const surahHeaderMarker =
      '    # Dedicated QUL font for surah_name lines:';

  final markerIndex = original.indexOf(startMarkerText);
  final surahHeaderIndex = original.indexOf(surahHeaderMarker);
  if (markerIndex == -1 || surahHeaderIndex == -1 || surahHeaderIndex < markerIndex) {
    throw StateError(
      'Could not locate the fonts: section markers in $_pubspecPath — '
      'refusing to rewrite it blindly.',
    );
  }
  final afterMarkerNewline = original.indexOf('\n', markerIndex + startMarkerText.length);
  if (afterMarkerNewline == -1) {
    throw StateError('Malformed $_pubspecPath: no newline after "$startMarkerText".');
  }
  final startIndex = afterMarkerNewline + 1;

  final fontsBlock = StringBuffer();
  for (int page = 1; page <= _expectedPageCount; page++) {
    fontsBlock.write('    - family: ${familyByPage[page]}\r\n');
    fontsBlock.write('      fonts:\r\n');
    fontsBlock.write('        - asset: $_fontsOutDir/p$page.ttf\r\n');
  }

  final newContent = original.replaceRange(
    startIndex,
    surahHeaderIndex,
    fontsBlock.toString(),
  );
  File(_pubspecPath).writeAsStringSync(newContent);
}
