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
/// Downloaded into `raw_resources/` (git-ignored — see .gitignore): the
/// first 3 on 2026-08-30 (Prompt 5), the 4th (surah names) also on
/// 2026-08-30 but during Prompt 6, once the ingestion step found
/// `surahs.name_arabic` had no source among the first 3 files, and the 5th
/// (surah header font) on 2026-08-31 during the Mushaf prototype step,
/// once surah_name lines turned out to need real Mushaf calligraphy that
/// neither the page fonts nor plain system text could give. The first 4
/// needed the user to download them manually (QUL gates those downloads
/// behind login); the 5th's font file is served from a public CDN with no
/// login wall, so this chat downloaded it directly. Checksums below were
/// computed against the actual downloaded files, not copied from anywhere.
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

  // --- Surah header font (spec section6 "Surah names" role) --------------
  // Neither the QCFxxx page fonts nor plain system text can give
  // surah_name lines real Mushaf-style calligraphy: the page fonts only
  // map presentation-form word-glyph codepoints, not ordinary Arabic
  // letters. This is a dedicated QUL font with one decorative ligature per
  // surah (user's explicit request, 2026-08-31 — "same font as the
  // ayahs" turned out to need its own dedicated resource, not reuse of
  // the page fonts).
  ResourceManifestEntry(
    resourceId: 'qul-surah-header-font',
    resourceName: 'Surah header font',
    provider: 'QUL',
    category: 'font',
    sourceUrl: 'https://qul.tarteel.ai/resources/font/458',
    downloadFormat: 'ttf',
    versionOrRevision: 'file dated 2026-01-05 (per CDN Last-Modified header)',
    licenseOrTermsUrl: 'https://www.tarteel.ai/terms',
    sha256:
        'de261a309bdd42262e1a268d5ead56b6ea8366cd59124baedea3903561d7370b',
    targetTableOrAssetPath: 'assets/fonts/surah_header/',
    compatibilityGroup: 'madinah-v2-qpc-v2-hafs',
    status: ResourceManifestStatus.pending,
    attributionText:
        'Surah header font (QCF_SurahHeader_COLOR) — Quranic Universal '
        'Library (qul.tarteel.ai).',
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

/// Resource manifest entries for the Tafsir module (Prompt 11, spec §11).
///
/// Sources: Tafsir Ibn Kathir, Tafseer Al-Saadi, and Iraab Al-Muyassar, all
/// Arabic, all from QUL's Tafsir directory
/// (https://qul.tarteel.ai/resources/tafsir). Ibn Kathir and As-Saadi match
/// spec §11's own recommendation by name; Iraab Al-Muyassar was chosen as
/// the "Arabic grammar/explanation source" over 4 other i'rab resources on
/// QUL (I'rab Al Quran li Al Darwish, Al Jadwal fi I'rab Al Quran, Tahlil
/// Kalimat al-Qur'an, Al-Muyassar fi Gharib al-Quran) because it's pitched
/// at general readers rather than being a heavier academic multi-volume
/// work — user's explicit choice, 2026-09-11, after being shown all 5
/// candidates.
///
/// Each resource's own detail page was checked before download (spec §11:
/// "Exact source choice must be confirmed against the resource detail page
/// and terms before release") — none of the 3 exposes a resource-specific
/// license distinct from the site-wide Terms of Use, same as every other
/// QUL resource already in this manifest, so `licenseOrTermsUrl` records
/// that same shared terms URL for all three, unchanged from the 5 entries
/// above.
///
/// Two Arabic As-Saadi resources exist on QUL (ids 24 and 308) with no
/// visible distinction between them on either page (no "supersedes"/
/// "deprecated" note, no differing author blurb). The user chose resource
/// 24 — the older/lower-numbered id, part of the same early batch as Ibn
/// Kathir's own id 22 — since there was no textual basis found to prefer
/// 308 (2026-09-11).
///
/// Downloaded manually into raw_resources/ on 2026-09-11 (QUL gates these
/// downloads behind login, same as the 4 Phase 1 resources above).
/// Checksums below were computed against the actual downloaded files.
const List<ResourceManifestEntry> tafsirModuleResourceManifestSeed = [
  ResourceManifestEntry(
    resourceId: 'qul-tafsir-ibn-kathir-ar',
    resourceName: 'Tafsir Ibn Kathir (Arabic)',
    provider: 'QUL',
    category: 'tafsir',
    sourceUrl: 'https://qul.tarteel.ai/resources/tafsir/22',
    downloadFormat: 'sqlite',
    versionOrRevision: 'file dated 2025-05-26 (per zip entry timestamp)',
    licenseOrTermsUrl: 'https://www.tarteel.ai/terms',
    sha256:
        'f8d1c43e5252c6b80891dbc9dd2602629af3ff2e9fb1d1ef669a9eafbe680ec7',
    targetTableOrAssetPath: 'tafsir_entries',
    compatibilityGroup: 'madinah-v2-qpc-v2-hafs',
    status: ResourceManifestStatus.pending,
    attributionText:
        'Tafsir Ibn Kathir, via Quranic Universal Library (qul.tarteel.ai).',
  ),

  ResourceManifestEntry(
    resourceId: 'qul-tafsir-saadi-ar',
    resourceName: 'Tafseer Al-Saadi (Arabic)',
    provider: 'QUL',
    category: 'tafsir',
    sourceUrl: 'https://qul.tarteel.ai/resources/tafsir/24',
    downloadFormat: 'sqlite',
    versionOrRevision: 'file dated 2025-05-26 (per zip entry timestamp)',
    licenseOrTermsUrl: 'https://www.tarteel.ai/terms',
    sha256:
        '9861b3520c9325137fa69dad14fb9c766f217def3e5d4b4ad4c555b8c54daec7',
    targetTableOrAssetPath: 'tafsir_entries',
    compatibilityGroup: 'madinah-v2-qpc-v2-hafs',
    status: ResourceManifestStatus.pending,
    attributionText:
        "Tafseer Al-Saadi (Abd al-Rahman ibn Nasir As-Sa'di), via Quranic "
        'Universal Library (qul.tarteel.ai).',
  ),

  ResourceManifestEntry(
    resourceId: 'qul-tafsir-iraab-muyassar-ar',
    resourceName: 'Iraab Al-Muyassar (Arabic)',
    provider: 'QUL',
    category: 'tafsir',
    sourceUrl: 'https://qul.tarteel.ai/resources/tafsir/504',
    downloadFormat: 'sqlite',
    versionOrRevision: 'file dated 2025-07-11 (per zip entry timestamp)',
    licenseOrTermsUrl: 'https://www.tarteel.ai/terms',
    sha256:
        '27db881913d11b4c5e2263d5b7bd69dec8be182cd40eb89445b6dbbb9885e257',
    targetTableOrAssetPath: 'tafsir_entries',
    compatibilityGroup: 'madinah-v2-qpc-v2-hafs',
    status: ResourceManifestStatus.pending,
    attributionText:
        "Al-I'rab Al-Muyassar, via Quranic Universal Library "
        '(qul.tarteel.ai).',
  ),
];

/// Resource manifest entries for the Morphology module (Prompt 12, spec
/// §12/§12.1/§12.2).
///
/// All 3 from QUL's Morphology directory
/// (https://qul.tarteel.ai/resources/morphology), the "Word by word"
/// variants (not the "Ayah by Ayah" ones QUL also lists) — matching spec
/// §12.1's per-word key (`surah:ayah:word_position`) rather than a
/// per-ayah grouping. Confirmed directly on that page there's no separate
/// part-of-speech/grammar-tag resource to pair with these, so
/// `morphology.part_of_speech`/`grammar_tags` stay NULL for this prompt
/// (spec §12.2: "Grammar tags (when available)").
///
/// Two of the three initial downloads (word-lemma, word-stem) came back
/// truncated twice in a row (a download-interruption issue, verified
/// byte-for-byte against each zip's own local-file-header declared size —
/// not a source-side defect); a third download attempt on 2026-09-13
/// finally completed both in full (zip integrity check clean). Checksums
/// below were computed against those complete files.
///
/// Each resource's own detail page was checked before download (spec §11's
/// "confirm against the resource detail page and terms" standard, applied
/// here too) — none exposes a license distinct from the site-wide Terms of
/// Use, same as every other QUL resource already in this manifest.
const List<ResourceManifestEntry> morphologyModuleResourceManifestSeed = [
  ResourceManifestEntry(
    resourceId: 'qul-morphology-word-root',
    resourceName: 'Word root',
    provider: 'QUL',
    category: 'morphology',
    sourceUrl: 'https://qul.tarteel.ai/resources/morphology/76',
    downloadFormat: 'sqlite',
    versionOrRevision: 'file dated 2025-07-09 (per zip entry timestamp)',
    licenseOrTermsUrl: 'https://www.tarteel.ai/terms',
    sha256:
        'a85c325c669fdf3295f8c150f9fbe780391ec9fc3c29b2c8b37b93083038db69',
    targetTableOrAssetPath: 'morphology',
    compatibilityGroup: 'madinah-v2-qpc-v2-hafs',
    status: ResourceManifestStatus.pending,
    attributionText:
        'Word root (Quranic morphology), via Quranic Universal Library '
        '(qul.tarteel.ai).',
  ),

  ResourceManifestEntry(
    resourceId: 'qul-morphology-word-lemma',
    resourceName: 'Word lemma',
    provider: 'QUL',
    category: 'morphology',
    sourceUrl: 'https://qul.tarteel.ai/resources/morphology/75',
    downloadFormat: 'sqlite',
    versionOrRevision: 'file dated 2025-07-09 (per zip entry timestamp)',
    licenseOrTermsUrl: 'https://www.tarteel.ai/terms',
    sha256:
        '8fd431f0b765d9a66e8ad584edbfc19bb2c62091bb1809a97666e47648f4a356',
    targetTableOrAssetPath: 'morphology',
    compatibilityGroup: 'madinah-v2-qpc-v2-hafs',
    status: ResourceManifestStatus.pending,
    attributionText:
        'Word lemma (Quranic morphology), via Quranic Universal Library '
        '(qul.tarteel.ai).',
  ),

  ResourceManifestEntry(
    resourceId: 'qul-morphology-word-stem',
    resourceName: 'Word stem',
    provider: 'QUL',
    category: 'morphology',
    sourceUrl: 'https://qul.tarteel.ai/resources/morphology/77',
    downloadFormat: 'sqlite',
    versionOrRevision: 'file dated 2025-07-09 (per zip entry timestamp)',
    licenseOrTermsUrl: 'https://www.tarteel.ai/terms',
    sha256:
        '57992661ebd776d2400fb129562ab931a7ea2211a8cd5b757d72e59556924784',
    targetTableOrAssetPath: 'morphology',
    compatibilityGroup: 'madinah-v2-qpc-v2-hafs',
    status: ResourceManifestStatus.pending,
    attributionText:
        'Word stem (Quranic morphology), via Quranic Universal Library '
        '(qul.tarteel.ai).',
  ),
];

/// The single Audio module (Prompt 13, spec §14) resource: Mishari Rashid
/// al-Afasy's Ayah-by-Ayah Murattal recitation with word-level segment
/// timing ("With segments" tag), Hafs — matches this project's
/// `madinah-v2-qpc-v2-hafs` compatibility group. Reciter chosen by the user
/// (no preference given; the most widely-used default reciter in Quran
/// apps was picked) from QUL's recitation resources list, which offers 80+
/// reciters; several others (as-Sudais, Abdul Basit, Al-Husary) also carry
/// the same 3 tags and would have worked equally well (2026-09-14).
///
/// This resource is metadata only — an `audio_url` per ayah (pointing at
/// `audio-cdn.tarteel.ai`) plus a segment-timing array — not the actual
/// mp3 bytes. Bundling full Quran recitation audio (many hundreds of MB to
/// low GBs) the way the 604 QPC V2 fonts were bundled isn't practical, so
/// playback streams `audio_url` directly at runtime instead (user's
/// explicit choice, 2026-09-14, alongside adding the `just_audio` package
/// dependency this requires — see pubspec.yaml).
///
/// Downloaded from the resource's own detail page
/// (https://qul.tarteel.ai/resources/recitation/118, "Download sqlite"),
/// same site-wide Terms of Use as every other QUL resource above. QUL's
/// own download names the file after its *internal* recitation id (953),
/// not the page id in the URL (118) — both are the same resource, verified
/// directly against the detail page's own documented JSON format
/// (`{surah, ayah, audio_url, segments}`) before ingesting.
///
/// Two real data-shape findings from inspecting the downloaded file
/// directly (not assumed from the resource's own docs), both handled in
/// `tool/ingest_quran_data.dart`'s `_buildAudio`/`_runAudioIntegrityChecks`
/// rather than papered over:
/// 1. The `verses` table's own `ayah_number` column is actually a
///    **global** 1-6236 index across the whole Quran (e.g. Al-Baqarah's
///    286 ayahs are numbered 8-293), not the per-surah number its name
///    suggests — verified against every surah's ayah count from the
///    already-ingested `surahs` table before trusting this reading, not
///    just from one example. Converted to the app's own per-surah
///    `ayah_number` at ingestion time.
/// 2. Each segment is `[array_index, word_position, start_ms, end_ms]`,
///    not the 3-element tuple the site's own docs show — verified
///    `array_index + 1 == word_position` holds for every individual
///    segment tuple, so the first element is redundant *within one tuple*.
///    It is NOT redundant across a whole ayah's segment list, though: in
///    61 of 6236 ayahs (e.g. 2:68) the reciter audibly repeats a phrase
///    mid-ayah, so the same `word_position` appears twice with two
///    different timestamps — `audio_segments.segment_index` therefore
///    stores the segment's own array position (always unique, preserves
///    playback order), not `word_position` (would collide on the second
///    occurrence). Most ayahs' segments stop at the last *real* word
///    (excluding the ayah-end marker, see `words.word_type`), 361 include
///    one extra segment for the marker itself (the recitation's own
///    verse-end pause), and 3 ayahs (11:44, 20:94, 37:102) have one
///    segment beyond even that — a genuine upstream alignment quirk, kept
///    verbatim rather than altered (CLAUDE.md rule #1's spirit). (Counts
///    per `tool/ingest_quran_data.dart`'s own run output, the authoritative
///    source — a slightly different manual spot-check count was seen
///    during investigation before the final per-ayah dedup logic landed.)
const List<ResourceManifestEntry> audioModuleResourceManifestSeed = [
  ResourceManifestEntry(
    resourceId: 'qul-recitation-mishari-alafasy-hafs',
    resourceName:
        'Mishari Rashid al-Afasy — Ayah-by-Ayah recitation + segments',
    provider: 'QUL',
    category: 'audio',
    sourceUrl: 'https://qul.tarteel.ai/resources/recitation/118',
    downloadFormat: 'sqlite',
    versionOrRevision: 'file dated 2025-05-27 (per zip entry timestamp)',
    licenseOrTermsUrl: 'https://www.tarteel.ai/terms',
    sha256:
        '1ce2eedfed2943d616fa64f31551332134e5a791ca06ee10c7ba72c81234ac9e',
    targetTableOrAssetPath: 'audio_assets, audio_segments',
    compatibilityGroup: 'madinah-v2-qpc-v2-hafs',
    status: ResourceManifestStatus.pending,
    attributionText:
        'Recitation by Mishari Rashid al-Afasy and word-level timing '
        'segments, via Quranic Universal Library (qul.tarteel.ai). Audio '
        'files themselves are streamed at playback time from '
        'audio-cdn.tarteel.ai, not bundled with the app.',
  ),
];
