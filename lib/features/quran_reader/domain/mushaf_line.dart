import 'surah.dart';
import 'word.dart';

/// `line_type` values from `mushaf_lines` (spec §6, §24: "all line_type
/// values are supported").
enum MushafLineType {
  ayah,
  surahName,
  basmallah;

  static MushafLineType fromValue(String value) {
    switch (value) {
      case 'ayah':
        return MushafLineType.ayah;
      case 'surah_name':
        return MushafLineType.surahName;
      case 'basmallah':
        return MushafLineType.basmallah;
      default:
        throw ArgumentError('Unsupported line_type: $value');
    }
  }
}

/// One rendered line of a Mushaf page (spec §6.2 renderer pipeline output).
///
/// [surah] is populated only for line_type == surah_name. [words] is
/// populated for line_type == ayah (that line's own words) and for
/// line_type == basmallah (always surah 1 ayah 1's words, reused — see
/// qpc_v2_fonts.dart doc comment on why).
class MushafLine {
  final int pageNumber;
  final int lineNumber;
  final MushafLineType lineType;
  final bool isCentered;
  final List<Word> words;
  final Surah? surah;

  const MushafLine({
    required this.pageNumber,
    required this.lineNumber,
    required this.lineType,
    required this.isCentered,
    this.words = const [],
    this.surah,
  });
}
