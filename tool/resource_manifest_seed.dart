library;

import 'package:quran_app/core/resource_manifest/resource_manifest_entry.dart';

/// Resource manifest entries for the 4 files identified/downloaded across
/// Prompt 5 and Prompt 6 (spec §6.1, §7, §8, §5 Metadata row) for the
/// Phase 0 Mushaf prototype.
///
/// These are written to the `resource_manifest` table by
/// `tool/ingest_quran_data.dart` (Prompt 6), which calls
/// `ResourceManifestEntry.toMap()` on each of these while it also imports
/// the actual Quran data from the same files. This file is the durable,
/// reviewable record of exactly what was selected and verified, so that
/// step doesn't depend on chat history.
///
/// Downloaded by the user into `raw_resources/` (git-ignored — see
/// .gitignore): the first 3 on 2026-08-30 (Prompt 5), the 4th
/// (surah names) also on 2026-08-30 but during Prompt 6, once the ingestion
/// step found `surahs.name_arabic` had no source among the first 3 files.
/// Checksums below were computed against the actual downloaded files, not
/// copied from anywhere.
///
/// Status is `pending`, not `active`: per spec §27, every resource must be
/// checked against its own terms/license page before production
/// redistribution — that review hasn't happened yet, only development use.

const List<ResourceManifestEntry> phase0ResourceManifestSeed = [
  // --- Mushaf Layout (spec section6, section6.1) ---------------------------------
  ResourceManifestEntry(
    resourceId: 'qul-mushaf-layout-kfgqpc-v2-1421h',
    resourceName: 'KFGQPC V2 layout (1421H print)',
    provider: 'QUL',
    category: 'mushaf-layout',
    sourceUrl: 'https://qul.tarteel.ai/resources/mushaf-layout/10',
    downloadFormat: 'sqlite',
    // QUL doesn't publish a semantic version for this resource; recording
    // the file's own internal modified date as the closest thing to a
    // revision marker (from the downloaded qpc-v2-15-lines.db.zip entry).
    versionOrRevision: 'file dated 2025-11-18 (per zip entry timestamp)',
    licenseOrTermsUrl: 'https://www.tarteel.ai/terms',
    sha256:
        '697cbc7f16db1f56b6d95c4d11a9eea074ad4759babd2d75abcad5738e2fdf96',
    targetTableOrAssetPath: 'mushaf_lines',
    compatibilityGroup: 'madinah-v2-qpc-v2-hafs',
    status: ResourceManifestStatus.pending,
    attributionText:
        'King Fahd Quran Printing Complex — Mushaf layout (1421H print), '
        'via Quranic Universal Library (qul.tarteel.ai).',
  ),

  // --- Quran Script (spec section8) ---------------------------------------------
  ResourceManifestEntry(
    resourceId: 'qul-quran-script-qpc-v2-glyph-wbw',
    resourceName: 'QPC V2 Glyph - Word by Word',
    provider: 'QUL',
    category: 'quran-script',
    sourceUrl: 'https://qul.tarteel.ai/resources/quran-script/61',
    downloadFormat: 'sqlite',
    versionOrRevision: 'file dated 2025-05-28 (per zip entry timestamp)',
    licenseOrTermsUrl: 'https://www.tarteel.ai/terms',
    sha256:
        'a766a033cad47b36f00f493f5f0541d5f07e1336857eaa6feba92465af3f68bb',
    targetTableOrAssetPath: 'words',
    compatibilityGroup: 'madinah-v2-qpc-v2-hafs',
    status: ResourceManifestStatus.pending,
    attributionText:
        'King Fahd Quran Printing Complex — QPC V2 glyph script, '
        'via Quranic Universal Library (qul.tarteel.ai).',
  ),

  // --- Font (spec section7) -------------------------------------------------
  ResourceManifestEntry(
    resourceId: 'qul-font-qpc-v2',
    resourceName: 'QPC V2 Font',
    provider: 'QUL',
    category: 'font',
    sourceUrl: 'https://qul.tarteel.ai/resources/font/249',
    downloadFormat: 'ttf',
    versionOrRevision: 'files dated 2024-10-15 (per zip entry timestamps)',
    licenseOrTermsUrl: 'https://www.tarteel.ai/terms',
    sha256:
        '9ead3836904f22324b5805c079c2911e13f384f2ca820254a36b8a22c28de555',
    // Not a DB table - 604 page-specific font files (p1.ttf .. p604.ttf),
    // one per Mushaf page. Target path is where they'll be unpacked to.
    targetTableOrAssetPath: 'assets/fonts/qpc_v2/',
    compatibilityGroup: 'madinah-v2-qpc-v2-hafs',
    status: ResourceManifestStatus.pending,
    attributionText:
        'King Fahd Complex for the Printing of the Holy Quran — QPC V2 '
        'font (calligraphy by Usman Taha), via Quranic Universal Library '
        '(qul.tarteel.ai).',
  ),

  // --- Surah metadata (spec section5 "Metadata" row, section6 "Surah names") ---
  // Neither of the 3 resources above carries Arabic surah names — only
  // surah_number. `surahs.name_arabic` (schema.dart) needs a real source.
  // Per spec section5 the primary candidate for Metadata is quran-assets,
  // fallback is QUL metadata ("choose the cleaner, more complete schema").
  // The user chose the QUL fallback explicitly (2026-08-30) over
  // quran-assets/metadata/surah-info.json.
  ResourceManifestEntry(
    resourceId: 'qul-quran-metadata-surah-names',
    resourceName: 'Surah names (QUL Quran Metadata)',
    provider: 'QUL',
    category: 'quran-metadata',
    sourceUrl: 'https://qul.tarteel.ai/resources/quran-metadata/70',
    downloadFormat: 'json',
    // QUL doesn't publish a semantic version for this resource; recording
    // the file's own internal modified date as the closest thing to a
    // revision marker (from the downloaded zip entry timestamp).
    versionOrRevision: 'file dated 2025-07-16 (per zip entry timestamp)',
    licenseOrTermsUrl: 'https://www.tarteel.ai/terms',
    sha256:
        'e0118c8aab8a25aa81b9e722479a2875520285d00a34a213331cefc8b0670ded',
    targetTableOrAssetPath: 'surahs',
    compatibilityGroup: 'madinah-v2-qpc-v2-hafs',
    status: ResourceManifestStatus.pending,
    attributionText:
        'Surah names — Quranic Universal Library (qul.tarteel.ai), '
        'Quran Metadata resource.',
  ),
];

/// Facts verified directly against the downloaded files (2026-08-30),
/// recorded here so Prompt 6 doesn't need to re-derive them:
///
/// `qpc-v2-15-lines.db` -> table `pages(page_number, line_number,
/// line_type, is_centered, first_word_id, last_word_id, surah_number)` +
/// table `info(name, number_of_pages, lines_per_page, font_name)` with row
/// ('QCF V2 ( 1421H print )', 604, 15, 'v2'). `line_type` values present:
/// 'surah_name', 'ayah', 'basmallah' - matches spec section6 exactly.
///
/// `qpc-v2.db` -> table `words(id, location, surah, ayah, word, text)`,
/// 83,668 rows. `location` format is 'surah:ayah:word' (e.g. '1:1:1'),
/// matching spec section8's word-key pattern. Word count should be
/// cross-checked against expected totals during Prompt 6/16's integrity
/// checks (spec section24) rather than assumed correct here.
///
/// `QPC V2 Font.ttf.bz2` -> despite the name, this is a ZIP (not bzip2) of
/// 604 files named `p1.ttf` .. `p604.ttf`, one per Mushaf page - matches
/// the page-specific font naming spec section7 warns about ("use the
/// exact family names included with the downloaded font package rather
/// than hard-code a guessed family"). The actual @font-face family name
/// per page still needs to be read from each ttf's own metadata when the
/// renderer prototype (Prompt 7) is built - not guessed here.
///
/// `quran-metadata-surah-name.json.zip` -> a single JSON object keyed by
/// surah id ("1".."114"), each value
/// `{id, name, name_simple, name_arabic, revelation_order, revelation_place,
/// verses_count, bismillah_pre}`. Ingestion (tool/ingest_quran_data.dart)
/// maps: id->surah_id, name_arabic->name_arabic (unchanged, per rule #1),
/// name_simple->name_transliteration, revelation_place->revelation_place
/// (stored as-is, e.g. "makkah"/"madinah" - not reworded to "Meccan" etc.),
/// verses_count->ayah_count. `name_english` (a translated meaning like "The
/// Opener") isn't present in this resource and is left NULL rather than
/// invented.
const String phase0ResourceManifestNotes = '''
See doc comments above each entry and on this constant's declaration.
''';
