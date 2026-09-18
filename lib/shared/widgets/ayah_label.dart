import '../../features/quran_reader/domain/quran_repository.dart';

/// Resolves `surah:ayah` to a human-readable Arabic label ("سورة البقرة،
/// آية ٧") — shared by any feature that lists ayahs by key (bookmarks,
/// notes, ...) so the format can't drift between them.
Future<String> resolveAyahLabel(
  QuranRepository repository,
  String ayahKey,
) async {
  final parts = ayahKey.split(':');
  final surahId = int.parse(parts[0]);
  final ayahNumber = int.parse(parts[1]);
  final surah = await repository.getSurah(surahId);
  return '${surah.nameArabic}، آية $ayahNumber';
}
