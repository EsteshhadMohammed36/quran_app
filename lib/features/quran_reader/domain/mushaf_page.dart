import 'mushaf_line.dart';

/// One Mushaf page: its exact, ordered line structure (spec §6.3 — never a
/// reflowing paragraph).
class MushafPage {
  final int pageNumber;
  final List<MushafLine> lines;

  const MushafPage({required this.pageNumber, required this.lines});
}
