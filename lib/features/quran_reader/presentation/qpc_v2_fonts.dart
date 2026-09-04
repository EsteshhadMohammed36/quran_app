import 'qpc_v2_font_families.g.dart';

/// QPC V2 is a page-specific font: every Mushaf page ships its own font
/// file and its own font-family name (spec §7). Family names were read
/// from each of the 604 bundled files' actual 'name' table, not guessed —
/// see tool/extract_qpc_v2_fonts.dart, which produced both the bundled
/// font assets and [generatedQpcV2FontFamilyByPage]. The section §25
/// prototype validated the renderer on 4 sample pages before this map
/// covered all 604 (CLAUDE.md rule #5).
const Map<int, String> qpcV2FontFamilyByPage = generatedQpcV2FontFamilyByPage;

/// `mushaf_lines` basmallah rows carry no first_word_id/last_word_id, so
/// there is no per-page word data for them, and no page font has a working
/// composed Bismillah glyph either: U+FB50 is mapped in every page font's
/// cmap (looked like a plausible reserved slot) but its glyph has zero
/// contours in both p601.ttf and p604.ttf (checked directly via the font's
/// glyf table, not assumed) — an empty placeholder, not real artwork. The
/// standard Unicode ligature U+FDFD renders, but in a plain system-font
/// style that doesn't match the surrounding Uthmani calligraphy at all.
///
/// Surah 1, ayah 1 *is* the Bismillah — a real ayah, already sourced from
/// `words` with full QCF calligraphy (spec §22/CLAUDE.md rule #1: this is
/// genuine Quran data, not invented text). Every basmallah line reuses
/// the first 4 of those 5 words (the 5th is that ayah's own end-of-ayah
/// number glyph, trimmed in sqlite_quran_repository.dart since a
/// basmallah line is never itself a numbered ayah — see that file's
/// comment), always rendered with this font specifically, since
/// `QCF2001` is the only page font that actually contains their glyphs.
const String qcfBasmallahFontFamily = 'QCF2001';


/// Looks up the bundled font family for [pageNumber], or `null` if that
/// page's font hasn't been bundled (see [qpcV2FontFamilyByPage]).
String? fontFamilyForPage(int pageNumber) => qpcV2FontFamilyByPage[pageNumber];
