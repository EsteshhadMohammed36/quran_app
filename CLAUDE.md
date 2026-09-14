# Quran App — Project Rules

Flutter app: a Mushaf-first Quran reader with a contextual ayah study layer
(meaning, morphology, grammar, tafsir, audio), built on `quran-assets` +
resources from the Quranic Universal Library (QUL).

**Full spec:** [docs/spec.md](docs/spec.md) — read the relevant section there
before implementing anything not covered by the rules below. Don't assume;
check the spec section number and quote/follow it.

## Non-negotiable rules

1. **Never transform Quran source text.** No auto-correct, spell-check,
   normalization, transliteration, or "cleanup" of canonical Quran script,
   ever — not even inside a helper/util function. (spec §22)
2. **Never build the Mushaf page as a normal reflowing paragraph.** It must
   render exactly the line structure (`page_number`, `line_number`,
   `line_type`) supplied by the selected Mushaf Layout — no width-based
   word-wrap. (spec §6.3)
3. **Ayah selection is semantic, not word-level.** Tapping any word inside an
   ayah must resolve to `surah:ayah`, then select and highlight the *whole*
   ayah. (spec §9)
4. **One canonical source per feature.** Don't duplicate data that already
   exists cleanly in `quran-assets`; only pull from QUL to fill an actual
   gap. Every imported dataset needs a `resource_manifest` entry (source URL,
   version, checksum, license/terms URL) — no exceptions, no "I'll add the
   manifest later." (spec §5, §16, §27)
5. **Don't scale past the validated prototype.** The Mushaf renderer
   (layout + script + font stack) must be proven on page 1, a multi-surah
   page, a mid-range page, and page 604 before any other feature is built on
   top of it. (spec §25)
6. **Lazy-load pages.** Never render/keep all 604 pages in memory at once;
   cache a small window of nearby pages only. (spec §21)

## Architecture (spec §17)

```
lib/
  core/       database/  assets/  resource_manifest/  errors/
  features/   quran_reader/  ayah_study/  tafsir/  morphology/
              audio/  bookmarks/  notes/  search/
                (each feature: data/ domain/ presentation/)
  shared/     widgets/  theme/
```

UI widgets depend on domain interfaces (Repository classes), never on raw
QUL/SQLite rows directly. State management: Provider (spec §17.1).

## Current phase

<!-- Update this section as work progresses so a fresh session (after
     /clear) knows where things stand without re-reading the whole spec. -->

- [x] Phase 0 — Mushaf prototype validated (spec §25) — built on the `mushaf-prototype` branch: `lib/features/quran_reader/{domain,data,presentation}` (Surah/Ayah/Word/MushafLine/MushafPage models, `QuranRepository`/`SqliteQuranRepository` per §18, `MushafPageView` — fixed line structure, no reflow, per §6.3/rule #2 — and `MushafPrototypeScreen`: full-screen page content, swipe between the 4 prototype pages, no permanent chrome, tap toggles a small page-number badge — wired as `main.dart`'s home). All 4 pages preloaded once up front (local SQLite, not a backend — no reload/spinner on swipe); `MushafPageView`'s lines each get an `Expanded` share of the full page height so short pages spread across the whole screen like a real printed Mushaf — except page 1 (Al-Fatiha), which the real printed Mushaf treats as a compact title page and keeps its natural top-aligned size (user's explicit call, 2026-08-31). `surah_name` lines now use a 5th resource, the QUL "Surah header font" (`assets/fonts/surah_header/`, `tool/resource_manifest_seed.dart` updated, `assets/database/quran.db` regenerated with 5 resource_manifest rows) — one decorative "سورة + name" banner ligature per surah (`surah_header_ligatures.dart`, all 114 codepoints extracted directly from the resource's own published table, not hand-copied), not the page-specific QCFxxx font (which can't render ordinary Arabic letters) or plain system text. Fonts: only the 4 required pages' QCF V2 fonts bundled (`assets/fonts/qpc_v2/`), family names read from each file's own `name` table, not guessed (§7). Basmallah lines reuse surah 1 ayah 1's real words (genuine Quran data, not invented text) rendered with the `QCF2001` font specifically — matches the real Mushaf calligraphy exactly (user's request, 2026-08-31), after two rejected attempts: U+FB50 (present in every page font's cmap but verified empty — zero contours in the `glyf` table) and the generic Unicode ligature U+FDFD (rendered but in a plain system-font style that didn't match the surrounding calligraphy). Visually verified on the Pixel 6 API 34 emulator on all 4 required pages (page 1, page 601 — 3 surah headers, page 300 — mid-range, page 604 — last page): correct word/ayah order, correct surah names, working basmallah, no missing glyphs, no reflow. `flutter analyze`/`flutter test`: clean.
  - While starting this, found and fixed a real Quran-text corruption bug in the Prompt 6 ingestion pipeline (Windows default process encoding, not UTF-8) that had already reached `main`/GitHub — fixed with a permanent byte-level integrity check added to `tool/ingest_quran_data.dart`, `quran.db` regenerated, verified byte-for-byte against source. See git history on `main` for the full writeup.
  - UI pass to match the real printed Madinah Mushaf look (2026-08-31): the default `ColorScheme.fromSeed(deepPurple)` theme was tinting the whole page a pale lavender and putting a mismatched grey `surfaceContainerHighest` band behind every surah-header banner (the ligature glyph already draws its own frame — see surah_name comment above — so that band was just a stray seam, not a real Mushaf feature). Replaced with `lib/shared/theme/mushaf_theme.dart`: a flat warm-white page (`mushafPageColor`) and near-black ink (`mushafInkColor`), wired into `MaterialApp.theme` in `main.dart` and into the ayah/basmallah `Text` styles in `mushaf_page_view.dart`; the surah-header container no longer paints a background at all. Pure app-chrome colors, not Quran content, so no resource_manifest entry (rule #4 doesn't apply). Re-verified visually on all 4 required pages on the same Pixel 6 API 34 emulator. `flutter analyze`/`flutter test`: clean.
  - Enlarged the surah-header banner (user's request, 2026-08-31): on the 15-line spread pages every line shares an equal `Expanded` slot of the page height, so the banner (a wide-short glyph) is clamped to fit that slot regardless of its own font size — bumping `fontSize` alone (70 → 84) only visibly grew it on page 1's natural-size title layout. Also trimmed the surah_name line's own vertical padding (4 → 1, ayah/basmallah lines unchanged) so the glyph uses more of its equal slot on every page type. Deliberately did *not* give surah_name lines extra flex/height budget over ayah lines — the real Madinah Mushaf's 15 line-slots per page are all equal height, banner included, so a taller banner slot would be less authentic, not more.
  - Stretched the surah-header banner to the full line width (user's explicit choice among 3 options, 2026-08-31 — accepted the horizontal-stretch distortion over overflowing into neighboring lines or a hand-drawn frame): `surah_name`'s `FittedBox` now uses `BoxFit.fill` instead of `scaleDown` (ayah/basmallah lines unchanged — stretching real Quran glyph text would mangle word spacing, rule #1). Hit a real Flutter gotcha getting there: `Container(alignment: ...)` inserts an inner `Align`, and `Align` always *loosens* the constraints it gives its child, so the `FittedBox` was only ever hugging the ligature's natural size — `BoxFit.fill` had nothing to stretch into no matter what (confirmed by temporarily coloring the `FittedBox`'s own box, which showed it was already exactly glyph-sized, not container-sized). Fixed by moving alignment onto `FittedBox`'s own `alignment` param and dropping `Container`'s, so the tight width from `width: double.infinity` reaches it undiluted. Re-verified visually on page 1 and page 601 (3 banners, all full-width) on the same Pixel 6 API 34 emulator.
  - Reverted the banner back to ayah-text size (user's request, 2026-08-31, "make the surah name the same size as the ayah words" — supersedes the two immediately preceding entries): `surah_name`'s `fontSize` is back to 28 (matching ayah/basmallah) and its `FittedBox` is back to `BoxFit.scaleDown` like every other line, no more `BoxFit.fill` stretch. Re-verified visually on page 1 and page 601 (3 banners) on the emulator — banners now read as small pill-shaped labels the same optical size as the surrounding ayah text, not full-width stretched bands.
  - Bumped `fontSize` 28 → 44 (user flagged the banner still read visibly smaller than the ayah text at the numeric match, 2026-08-31 pt.2; this update was made but not logged at the time — recorded now for the record while touching this same code). Calibrated by measuring on-device ink pixel height on page 601 rather than trusting the fontSize number: 27px banner ink vs. 42px ayah ink both at fontSize 28, so 44 (28 × 42/27) was the corrected value. `FittedBox` stayed `BoxFit.scaleDown`.
  - Full width + bigger, again (user's request, 2026-08-31 pt.3): even at `fontSize: 44` the `BoxFit.scaleDown` FittedBox was still clamping the banner down to fit its slot, so it kept reading smaller than the ayah lines, and it wasn't edge-to-edge. `surah_name`'s `FittedBox` now uses `BoxFit.fill` again (`fit` is conditional per line type in `_MushafLineView` — surah_name gets `fill`, ayah/basmallah stay `scaleDown`, so rule #1 still isn't touched: the ligature is a decorative banner glyph, not canonical ayah/basmallah text), with `alignment: Alignment.center` on the FittedBox. `fontSize: 44` is now moot (fill stretches to the slot regardless) but left in place. Re-verified visually via `adb screencap` on the Android emulator on all 4 required pages: page 1 (banner full-width), page 601 (3 banners, all full-width and readable), page 300 (no banner, unaffected), page 604 (3 banners full-width) — no distortion/overflow, ayah/basmallah lines unchanged. `flutter analyze`/`flutter test`: clean.
  - Same visual size as the basmallah, full width kept (user's request, 2026-08-31 pt.4, "اجعل اسم السورة يظهر بنفس الحجم البصري تقريبًا لحجم البسملة" — explicitly keep the full-width stretch, only fix the vertical size): first attempt measured the surah_name string's own natural height at `fontSize: 44` via `TextPainter` and used only that as the `SizedBox` height feeding `FittedBox`, reasoning `BoxFit.fill` would then have ~zero vertical room to stretch into and stay purely horizontal. Shipped, then found wrong by the user on-device — visibly *smaller* than before, not matching. Instrumented with a temporary debug `print` (reverted after) to get real on-device numbers instead of guessing further: at fontSize 44 the ligature's own natural logical height is 44, but its actual on-screen ink is only ~44 device px inside that box (the banner font bakes a lot of white space/framing into its glyph — measured on page 601: at an *equal* nominal size its ink is well under half the ayah/basmallah font's). The basmallah's own natural logical height is only 28 — smaller than the ligature's 44 — so handing FittedBox that 28 as the target *shrank* the banner (28px ink, worse than the 44px it had before). Bigger problem found in the same pass: the basmallah's own full-phrase ink (~99 device px, 4 words of stacked diacritics) is already taller than the entire 15-line slot budget (~49 logical / ~130 device px) — so pixel-matching the banner to the basmallah's ink is physically impossible without overlapping the neighboring line (rule #2's fixed line grid forbids that). The achievable fix: give surah_name the *same* full slot height every other line already gets (removed the special-cased measurement entirely — one shared, MediaQuery-derived `slotHeight`, no hardcoded px, for every line type) and let `BoxFit.fill` (surah_name only; every other line type stays `BoxFit.scaleDown`, unchanged) stretch it to fill that whole slot in both directions — full line width, and the largest height obtainable without breaking the line grid. Re-measured on-device via `adb screencap` + a small pixel-scanning script: banner ink grew from 28px (broken attempt) to 50px (up from the original 44px baseline too) — clearly bigger, though still short of the basmallah's outsized 99px 4-word ink, which the slot-height ceiling makes unreachable. `lib/features/quran_reader/presentation/mushaf_page_view.dart` only; ayah/basmallah styling, alignment, and spacing untouched throughout. Re-verified visually on page 1, page 601 (3 banners), and page 604 (3 banners) — full-width, noticeably bigger, no overflow/overlap into neighboring lines. `flutter analyze`/`flutter test`: clean.
  - Bigger flex share for `surah_name` + fixed the resulting empty margin (the flex/fontSize bump was made in an earlier session but not logged at the time — recorded now together with today's fix, 2026-09-03, while touching this same code): `MushafPageView`'s per-line `Expanded` now uses `flex: 3` for `surah_name` vs `flex: 1` for every other line type (previously all-equal flex), and `fontSize` moved 44 → 66, both for a more prominent banner. That surfaced a visible gap above/below the banner inside its now-larger slot (user flagged it today). Root-caused with a temporary debug `ColoredBox`/`Container.color` around the FittedBox, screenshotted on page 601, then pixel-scanned (`adb screencap` + a small PowerShell/`System.Drawing` script): the slot itself was genuinely being filled edge-to-edge, but the banner's *ink* (frame + text, the dark pixel band) only filled ~39% of that box's height (119px ink / 306px slot, and 120px / 307px on a second banner — consistent) — confirming the surah-header font's own line-height metrics bake in far more vertical blank space than the visible glyph, so `BoxFit.fill` was scaling that baked-in blank right along with the ink instead of eliminating it. Horizontal fill was already correct (ink measured ~29px–1049px of a 1080px-wide screenshot, i.e. edge-to-edge modulo this widget's own 8dp padding), so only the vertical axis needed a fix. Fix: an extra Y-only stretch (`Matrix4.diagonal3Values(1.0, 2.56, 1.0)`, `2.56 ≈ 1/0.39` from the measurement above) applied via a `Transform` wrapped in a `ClipRect` around the already-`BoxFit.fill`'d `FittedBox` — `ClipRect` keeps the now-overflowing extra stretch from spilling into the line above/below (rule #2's fixed grid). `ayah`/`basmallah` lines are untouched (the wrapping only applies when `isSurahName`). Debug coloring was removed before shipping. Re-verified visually via `adb screencap` on page 1, page 601 (3 banners), and page 604 (3 banners) — banner ink now fills its slot edge-to-edge vertically, no visible margin, no overflow into neighboring lines. `flutter analyze`/`flutter test`: clean.
  - Page 1 (Al-Fatiha) now spreads across the full page like every other page (user's request, 2026-09-03, "عاوزة ايات سورة الفاتحة تكون متوزعة ف الصفحة ومناسبه بصريا مش مرفوعة لوق كده" — reverses the 2026-08-31 "keep it a compact top-aligned title page" decision above): `MushafPageView` no longer special-cases `page.pageNumber == 1` — every page now unconditionally uses `MainAxisSize.max` with an `Expanded` per line, the same mechanism pages 601/300/604 already used. With only ~8 lines total, the old compact/top-aligned layout left a large dead-white block at the bottom of the screen, which read as content pushed up rather than a balanced page. Ayah lines' own `FittedBox` still uses `BoxFit.scaleDown` (never enlarges past its natural `fontSize: 28`), so this only redistributes the empty space *around* each line evenly down the page — it doesn't change glyph size, and doesn't touch rule #1 (still zero transformation of the Quran text itself) or rule #2 (still one fixed line per slot, no reflow). Re-verified visually via `adb screencap` on page 1 (ayahs now evenly spaced top-to-bottom, no dead space) and spot-checked page 601 unaffected. `flutter analyze`/`flutter test`: clean.
  - Pinned `surah_name` rows to a fixed height instead of a relative flex share (user's request, 2026-09-03, right after the page-1-spread change above: "اسم سورة الفاتحة يكون نفس الحجم بتاع باقي اسماء السور"): the page-1-spread fix made every page use `Expanded`/flex for line distribution, but a *relative* flex share means a surah_name row's slot height depends on how many other lines share its page — Al-Fatiha only has ~8 lines total vs. the standard 15, so `flex: 2` there gave it roughly double the fraction of the page that the same `flex: 2` gives on a 15-line page like 601/604, making its banner visibly bigger than every other surah's. Fix: `surah_name` lines are no longer wrapped in `Expanded` at all — they get a plain `SizedBox` with a height fixed at `MediaQuery.of(context).size.height * (2/18)` (`_surahNameRowHeight` in `MushafPageView`), the exact fraction a `flex: 2` row already got on a true 15-line page (12 flex:1 ayah/basmallah rows + 3 flex:2 surah_name rows = 18 flex units, so 2/18 per banner) — chosen so 601/604's already-approved banner size is reproduced exactly, not just approximated. Only `ayah`/`basmallah` rows stay `Expanded`, sharing whatever height is left over after the fixed-height rows are placed (Flutter's flex layout supports mixing fixed and flexible children in one `Column` natively). Verified with a pixel measurement, not just by eye: scanned the frame's own decorative left edge (x=30, avoids picking up ayah/basmallah ink at wider x/y ranges) on both page 1 and page 601 — both now measure the identical `y=143..365` (height 222px), i.e. pixel-for-pixel the same banner size. `flutter analyze`/`flutter test`: clean.
- [x] Phase 1 — Project structure + SQLite schema + resource manifest
  - [x] Project structure (`lib/core/*`, `lib/features/*/{data,domain,presentation}`) + deps (`provider`, `sqflite`, `path_provider`, `path`)
  - [x] SQLite schema (§15 tables + §15.1 indexes) — `lib/core/database/schema.dart` + `app_database.dart`
  - [x] Resource manifest bookkeeping (§16, §27) — `lib/core/resource_manifest/{resource_manifest_entry,resource_manifest_repository,sqlite_resource_manifest_repository}.dart`; `resource_manifest` table gained an `attribution_text` column (§27) not in the §16 list verbatim
  - [x] QUL resource download instructions — user downloaded 4 resources for the `madinah-v2-qpc-v2-hafs` group into `raw_resources/` (git-ignored): Mushaf layout (`qpc-v2-15-lines.db.zip`), Quran script (`qpc-v2.db.zip`), font (`QPC V2 Font.ttf.bz2`, actually a zip of 604 page fonts), surah names (`quran-metadata-surah-name.json.zip` — added mid-Prompt-6 once `surahs.name_arabic` turned out to have no source among the first 3; user chose the QUL fallback over quran-assets/metadata). Schemas verified by hand against spec §6/§8. Checksums + full metadata in `tool/resource_manifest_seed.dart`.
  - [x] Ingestion pipeline (§23/§23.1/§24) — `tool/ingest_quran_data.dart`: reads the 4 raw_resources files via the `sqlite3` CLI + `package:archive`, transforms to canonical schema, runs all §24 integrity checks, writes a fresh pre-populated `assets/database/quran.db` (114 surahs, 6236 ayahs, 83668 words, 9046 mushaf_lines, 4 resource_manifest rows — verified against live counts). `lib/core/database/app_database.dart` now copies this bundled asset to the documents dir on first run instead of on-device ingestion (user's explicit choice over in-app ingestion, 2026-08-30). `flutter analyze`/`dart analyze tool/`/`flutter test`: clean. Verified end-to-end on the Pixel 6 API 34 emulator (temporary debug print, reverted) — real device confirmed the asset-copy + query path works.
- [ ] Phase 2 — Ayah selection, context sheet, tafsir, morphology, audio
  - [x] Full 604-page reader + ayah selection/hit testing (Prompt 9, spec
    §9/§17.1/§21) — `MushafReaderScreen` (new, now `main.dart`'s home,
    superseding `MushafPrototypeScreen`) swipes across every page the
    installed layout has (`QuranRepository.getPageCount()`, not a
    hardcoded 604), lazily loading pages through the new
    `QuranReaderProvider` (spec §17.1) rather than the prototype's
    preload-everything-up-front approach: a small `Map` cache keyed by
    page number, evicted down to `currentPage ± 2` on every page-settle
    (rule #6/spec §21 — never all 604 pages in memory at once), with the
    two immediate neighbors prefetched so swiping stays instant. Tapping
    any word in `MushafPageView`/`_MushafLineView` resolves
    `Word.ayahKey` (`surah:ayah`, new getter) and highlights every word
    sharing that key across the whole rendered page — verified this
    correctly spans a Mushaf-line boundary (page 2, Al-Baqarah ayah 2
    wraps line 2→3; tapping either part highlighted both, ayah 1 on the
    same line stayed unhighlighted), i.e. spec §26's "Boundary ayah" case
    passes. Implemented as per-word `TextSpan`s with a
    `TapGestureRecognizer` each (same `TextStyle` as the old single-Text
    version, so glyph spacing/shaping is pixel-identical — verified, not
    assumed) rather than manual hit-testing, since manual hit-testing
    would've needed a page-level tap-outside-clears handler competing
    with per-word recognizers in the same gesture arena, a known Flutter
    footgun (nested tap detectors can double-fire); scoped "tap outside
    dismisses" out of this prompt instead, since spec §9.1 ties it to the
    context sheet's own UX rules, not built yet. `surah_name`/basmallah
    lines stay non-interactive (basmallah reuses Al-Fatiha 1:1's words
    for display only — selecting it while reading an unrelated surah's
    page would be semantically wrong per rule #3).
  - Bundled all 604 QPC V2 page fonts (previously only the 4 prototype
    pages' fonts were bundled, rule #5's gate — now satisfied). Extracted
    via new `tool/extract_qpc_v2_fonts.dart` from the already-manifested
    `raw_resources/QPC V2 Font.ttf.bz2` (`resource_id: qul-font-qpc-v2`,
    already covered the full 604-file resource — no new manifest entry
    needed, rule #4): reads each font's real family name from its own
    'name' table (spec §7 — confirmed, not assumed, all 604 follow
    `QCF2{page:03d}`), writes `assets/fonts/qpc_v2/p{1..604}.ttf`, and
    regenerates both `qpc_v2_font_families.g.dart` (the page→family map)
    and pubspec.yaml's `fonts:` section (604 entries) directly — hand-
    editing that many entries wasn't practical. User explicitly signed
    off on the size/repo-growth tradeoff first (2026-09-05): ~198MB
    uncompressed across 604 font files, comparable to other full-Mushaf
    apps. Visually verified on the Pixel 6 API 34 emulator: page 1
    (unchanged, word-splitting into spans didn't alter rendering), page 2
    (Al-Baqarah — never part of the original 4-page prototype set, so
    this is the first real proof all 604 fonts extract/load correctly,
    not just 4), tap-to-select/highlight-whole-ayah, switching selection
    between ayahs, and forward page navigation (RTL swipe: drag left-to-
    right advances page 1→2, matching real Mushaf page-turning).
    `flutter analyze`/`flutter test`: clean.
  - [x] Ayah Context Sheet (Prompt 10, spec §10) — new `AyahContextSheet`
    (`lib/features/ayah_study/presentation/`, a new feature per §17's
    architecture tree, depending on `quran_reader`'s domain/provider —
    the reverse dependency would be wrong) opens as a persistent
    `Scaffold.bottomSheet` (not `showModalBottomSheet` — spec §10 needs
    the Mushaf page to stay visible/tappable *around* it, which a modal
    barrier would block) whenever `QuranReaderProvider.isAyahSheetOpen`
    is true, which `selectWord`/`clearSelection` now toggle alongside
    `selectedAyahKey` (spec §9's flow ends with "... -> open Ayah Context
    Sheet"; §9.1 "Different ayah tapped" keeps the sheet open and its
    active tab unchanged, only resetting to the Meaning tab once the
    sheet fully closes). Shows the real surah name/ayah number/ayah text
    and a Meaning/Morphology/Grammar tab row (Qiraat shown per spec §10
    but disabled — it's explicitly "(future)" there) — tab bodies and the
    Tafsir/Note/Bookmark/Continue actions + audio row are non-blocking
    "not available yet" placeholders (spec §20), since those are later
    prompts (11-14), not this one.
    Two things came up while building this that weren't in the original
    plan for this prompt:
    - Rendering the selected ayah's own text needed each word's *page*
      number to pick that page's QCF font (spec §7) — a page-boundary
      ayah (spec §26) can have words from two different page fonts.
      Found `words.page_number` is actually always NULL in the shipped
      `quran.db` (an ingestion gap from Prompt 6, unnoticed until now
      since nothing had read that column before). Rather than touch the
      ingestion pipeline/regenerate the database (extra care territory,
      CLAUDE.md's own rule), added
      `QuranRepository.getPageNumbersForWordIndexes()`, which derives it
      at read time from `mushaf_lines`' own `first_word_id`/`last_word_id`
      ranges — the same authoritative source `getPage()` already uses,
      just queried in the other direction. `words.page_number` itself is
      still unpopulated dead weight in the schema; worth fixing at the
      source in a later ingestion pass, not urgent now that reads don't
      depend on it.
    - Prompt 9 had deliberately deferred "tap outside dismisses" (spec
      §9.1) to this prompt, planning to add a second, outer
      `GestureDetector` around the per-word `TapGestureRecognizer`s
      already shipped. Realized before writing it that two independent
      tap recognizers overlapping the same point don't reliably suppress
      one another in Flutter's gesture arena (nested detectors can both
      fire) — a real risk once a page needed both "tap a word selects"
      and "tap elsewhere dismisses" at once. Replaced the per-word
      recognizers with a single page-level `GestureDetector.onTapUp` in
      `MushafPageView` that does its own hit testing (a `GlobalKey` per
      ayah line's `Text.rich` + `RenderBox.globalToLocal` + a throwaway
      `TextPainter.getPositionForOffset`, mapped back to a word via each
      word's precomputed character range) — one recognizer total, so
      there's no arena conflict to reason about. Rendering is unaffected
      (same `TextSpan` builder feeds both the visible `Text.rich` and the
      hit-test `TextPainter`, so they can't drift apart).
    Visually verified on the Pixel 6 API 34 emulator: sheet opens on tap
    with correct surah/ayah/ayah-text (including correct calligraphy,
    confirming the page-number-lookup fix works), tab switching, tapping
    a *different* ayah while the sheet is open updates it in place and
    keeps the active tab (not reset to Meaning), the sheet's close button
    dismisses, and tapping a non-ayah area (the surah-header banner)
    while an ayah is selected also dismisses. `flutter analyze`/
    `flutter test`: clean.
  - [x] Tafsir Module (Prompt 11, spec §11/§11.1/§11.2) — sources: Tafsir
    Ibn Kathir, Tafseer Al-Saadi, Iraab Al-Muyassar, all Arabic, all from
    QUL's Tafsir directory (each resource's own detail page checked before
    download per spec §11 — none exposes a license distinct from the
    site-wide Terms of Use, same as the 5 existing manifest entries; user
    picked Al-Saadi resource 24 over an unexplained duplicate 308, and
    Iraab Al-Muyassar over 4 other i'rab resources, both 2026-09-11).
    `lib/core/database/schema.dart`'s `tafsir_entries` table gained
    `surah_id`/`ayah_number` columns (for FK/ordering, matching the
    ayahs/words tables' own convention) and `content` became nullable —
    verified directly against all 3 downloaded files that a group of
    consecutive ayahs sharing one tafsir passage stores the real text only
    on the group's first ("owning") ayah, with every other member ayah's
    row left NULL and `group_id` pointing back to the owner; every row
    (owner and members alike) carries `group_ayah_start`/`group_ayah_end`
    so a single row lookup already gives the full range, no join needed
    just to display it. `tool/ingest_quran_data.dart` extended (same
    single-pass pipeline, one combined `quran.db`, not a second db file)
    with byte-verified UTF-8 reads (already-shared `_querySqliteJson`) and
    new integrity checks: exactly 6236 entries per source, no
    duplicate/orphaned ayah_key, every group_id resolves to a real owning
    row, an Arabic-script sanity check on every owner's content. Two real
    (not bugs-in-the-checker) upstream data findings surfaced by those
    checks and deliberately *not* "fixed": As-Saadi has 59 standalone
    ayahs with genuinely no independent commentary in its own export, and
    4 As-Saadi rows (2:52, 2:53, 2:103, 23:38) hold a single placeholder
    symbol ("×"/"*"/"-") instead of Arabic text — both verified against
    the raw source file directly, kept verbatim rather than papered over
    (rule #1's spirit: never invent/alter). New row counts: 3
    `tafsir_sources`, 18708 `tafsir_entries` (3 × 6236), 8
    `resource_manifest` rows total. `lib/features/tafsir/domain`:
    `TafsirSource`/`TafsirEntry`/`TafsirGroup` entities +
    `TafsirRepository` interface matching spec §11.2's method set exactly
    (`getSources`/`getEntry`/`getGroup`/`search`).
    `lib/features/tafsir/data/sqlite_tafsir_repository.dart`: `getEntry`
    resolves the group-owner indirection via a self-join so callers never
    see the raw NULL-on-members storage shape; `search` is a plain SQL
    `LIKE` over owner rows' content (MVP scope, not full-text
    search/ranking — good enough for spec §11.2's method signature, no
    normalization of diacritics). `lib/features/tafsir/presentation/
    tafsir_screen.dart`: `TafsirScreen` per spec §11.1's exact structure
    (Selected Ayah header incl. real ayah text via the newly-shared
    `QuranAyahText` widget, accordion of the 3 sources — single-open, one
    search box scoped to whichever source is expanded since
    `TafsirRepository.search` takes a `sourceId` — Previous/Current/Next
    ayah navigation crossing surah boundaries at 1:1/114:6, a font-size
    slider, Return to Mushaf). Opened via a full-screen `Navigator.push`
    from `AyahContextSheet`'s now-enabled "تفسير" action (previously a
    disabled placeholder) — deliberately not another bottom sheet, since
    this needs room for multiple accordion sources plus nav/search/font
    controls at once. `TafsirScreen` takes the *same*
    `QuranReaderProvider` instance as an explicit constructor param
    (not looked up via `Provider.of`/`context.read`) because a route
    pushed this way isn't a descendant of the `ChangeNotifierProvider`
    wrapping the reader's own widget tree — ambient lookup would throw;
    every Previous/Next step calls `QuranReaderProvider.selectAyahKey`
    (new method) directly so "Return to Mushaf" always shows the
    last-viewed ayah selected (spec §11: "without losing ayah identity").
    `lib/features/tafsir/presentation/tafsir_html_text.dart`: a small
    presentation-only HTML-tag stripper for the sources' HTML-ish content
    (no new dependency added — kept pubspec's existing minimal dependency
    set rather than pulling in a full HTML-rendering package for this).
    `AyahContextSheet`'s own ayah-text rendering (`_AyahText`) was
    extracted into `lib/shared/widgets/quran_ayah_text.dart` as public
    `QuranAyahText` so both surfaces share one implementation of this
    Quran-text/per-page-font rendering logic rather than risking two
    copies silently diverging.
    Verification: `flutter analyze`, `dart analyze tool/`, and
    `flutter test` all clean throughout. Visually verified on the Pixel 6
    API 34 emulator: the Tafsir action opens `TafsirScreen` with the
    correct selected ayah (Al-Baqarah 2:3/2:4, correct calligraphy via the
    shared widget — first real proof `QuranAyahText` still renders
    correctly after the extraction), all 3 sources listed in the
    accordion with correct name/author (Iraab Al-Muyassar correctly shows
    no author line, not an invented one), Previous/Next navigation moving
    the selection and syncing back to the Mushaf reader's own selection
    state on return. The underlying group-resolution/search SQL (the
    exact queries `SqliteTafsirRepository` runs) was additionally verified
    directly against the shipped `quran.db` via the `sqlite3` CLI for a
    real 11-ayah group (Ibn Kathir, Al-'Adiyat 100:1-100:11) and a search
    query, independent of the on-device UI pass. Accordion expand/collapse
    and the font-size slider's visual effect were exercised in an earlier
    run of this same build before an emulator restart interrupted the
    session (not independently re-confirmed after the restart — flaky
    touch-input dispatch on the restarted emulator instance blocked
    further on-device interaction, confirmed unrelated to the app itself
    since even the Android home screen stopped responding to `adb input
    tap` at the same time `adb input keyevent` kept working).
  - [x] Morphology Module (Prompt 12, spec §12/§12.1/§12.2) — root/lemma/
    stem now populated for real (see the 2026-09-14 entry below for how the
    data blocker resolved and how ingestion/wiring finished); `part_of_
    speech`/`grammar_tags` stay permanently NULL, matching spec §12.2's own
    "(when available)" — no such resource exists on QUL to pair with these
    three. What follows is the original, still-accurate build history.
    Two of the three raw_resources downloads
    needed for root/lemma/stem ingestion (`word-lemma.db.zip`,
    `word-stem.db.zip`) fail a zip integrity check (no EOCD record —
    truncated/corrupted download); `word-root.db.zip` alone is fine
    (verified: `roots`/`root_words` tables, `word_location` key matches
    spec §12.1's `surah:ayah:word_position` format exactly). Ingestion
    pipeline work is on hold until both are re-downloaded from
    [QUL's morphology resources page](https://qul.tarteel.ai/resources/morphology)
    (word-by-word variants, not ayah-by-ayah) — confirmed directly against
    that page there's no separate POS/grammar-tag resource file to pair
    with them, so `morphology.part_of_speech`/`grammar_tags` will stay
    NULL for this prompt (matches spec §12.2's "(when available)").
    In the meantime, fixed a real naming bug this surfaced in the Ayah
    Context Sheet's study tabs (`ayah_context_sheet.dart`): `StudyTab
    .morphology`'s tab was labeled "الإعراب" and `StudyTab.grammar`'s was
    labeled "النحو" — backwards against spec §12 (morphology =
    root/lemma/stem/POS) vs §13 (grammar = syntactic i'rab analysis).
    Relabeled to "الصرف" (morphology) / "الإعراب" (grammar), and since
    "الإعراب" now correctly names spec §13's i'rab module, wired it to
    real content instead of a placeholder: it reads the already-ingested
    Iraab Al-Muyassar tafsir source (Prompt 11) directly via
    `TafsirRepository.getEntry` (new `_GrammarTabContent` widget;
    `iraabMuyassarSourceId` constant added to `tafsir_source.dart` so the
    source_id isn't a duplicated magic string) — CLAUDE.md rule #4 (one
    canonical source per feature), since this is genuinely the same i'rab
    data spec §13 wants, not a separate dataset. "الصرف" itself stays a
    placeholder pending the two corrupted downloads. `flutter analyze`/
    `flutter test`: clean. Verified visually on the Pixel 6 API 34
    emulator: tab labels correct, "الإعراب" shows real i'rab text for
    1:4 ("مالك: صفة رابعة لله"), "الصرف" still shows its not-available
    placeholder.
  - Two bug fixes to the Ayah Context Sheet found after the above (both
    2026-09-13, `ayah_context_sheet.dart` only):
    1. **Overflow.** `_AyahSheetBody` rendered the whole sheet (header,
       ayah text, tabs, tab content, actions, audio) as one plain
       `Column` with no height cap; since the sheet is a persistent
       `Scaffold.bottomSheet` (not modal), a long الإعراب/tafsir passage
       could push the total past the screen height and throw a
       `RenderFlex overflowed` error (user-reported). Fixed by capping
       the sheet at 80% of screen height (`ConstrainedBox`) and making
       only the variable middle (ayah text + tabs row + active tab
       content) a `Flexible` + `SingleChildScrollView` — header/actions/
       audio stay pinned, only the part that can grow arbitrarily long
       now scrolls internally. Also bumped `_MorphologyTabContent`'s
       word-card strip from 260px to 300px — `flutter test` surfaced a
       ~20px internal overflow in `_MorphologyWordCard`'s own column
       (5 label/value field rows didn't quite fit), a separate bug of
       the same kind.
    2. **RTL alignment.** "الإعراب" tab text rendered left-aligned
       ("مكتوبة من الشمال", user-reported) — `_GrammarTabContent` was the
       one Arabic text block in the file missing the explicit
       `Directionality(textDirection: TextDirection.rtl)` wrapper every
       other Arabic block in the app uses (`QuranAyahText`,
       `MushafReaderScreen`, `_MorphologyTabContent`'s word text) — the
       app sets no locale/Directionality globally, so `CrossAxisAlignment
       .start`/default `TextAlign` resolved to the left. Wrapped it the
       same way as the rest.
    Verified on-device (physical Android 15 phone, connected via adb —
    the Pixel 6 API 34 emulator kept crashing shortly after boot in this
    session's sandboxed environment; see the next entry for the fix that
    got it booting headless). `flutter analyze`/`flutter test`: clean
    (one pre-existing, unrelated test-mechanics failure in
    `test/morphology_tab_scroll_test.dart` — a drag-distance issue in the
    test itself, not an overflow — left as-is).
  - **Data blocker resolved + Morphology ingestion completed** (2026-09-14,
    continuing the session above). `word-lemma.db.zip`/`word-stem.db.zip`
    were re-downloaded a third time and finally passed zip integrity —
    confirmed a download-interruption issue, not a source-side defect
    (`tool/resource_manifest_seed.dart`'s `morphologyModuleResourceManifestSeed`,
    3 new rows, documents this). `tool/ingest_quran_data.dart` extended
    (same single-pass pipeline) to extract all 3 word-root/word-lemma/
    word-stem resources, join each word-location junction table back to
    its dictionary table, and populate the already-existing `morphology`
    table with exactly one row per `words` row — root/lemma/stem `null`
    where a word genuinely has none (particles, pronouns — most of QUL's
    own `root_words`/`lemma_words`/`stem_words` tables already skip these),
    plus new integrity checks (row-count parity with `words`, no duplicate/
    orphaned `word_location`, an Arabic-script sanity check per entry).
    `assets/database/quran.db` regenerated (83668 morphology rows; 11
    resource_manifest rows total).
    Cross-checked the join's correctness directly against both raw
    sources with the `sqlite3` CLI (not just trusting the integrity
    checks passing) after noticing something that looked at first like an
    off-by-one: `words` (from the qpc-v2 script resource, unrelated to
    this prompt) stores one extra "word" per ayah beyond the
    root/lemma/stem resources' own count — e.g. Al-Fatiha 1:1 has 5 rows
    in `words` but the root resource only goes up to `1:1:4`. Traced this
    to `words`' *last* position in every ayah being the ayah-end/verse-
    ornament marker glyph (confirmed pattern-wise: root/lemma's own
    per-ayah max position is always exactly `words`' max position for
    that ayah minus 0 or more, never *more* — checked across all 6236
    ayahs, zero exceptions), not a real word — so the two sources' word
    numbering does line up correctly for every real word; the marker
    position simply and correctly gets no root/lemma/stem. Verified
    against real content, not just position math: e.g. 2:2's root entries
    at positions 2/4/6/7 resolve to "الكتاب"/"ريب"/"هدى"/"للمتقين" exactly
    (skipping the demonstrative/negation/preposition words 1/3/5, which
    have none) — correct. No data bug; false alarm caught before being
    reported as one.
    `lib/features/morphology/{domain,data,presentation}` (created earlier
    this session, before the data blocker above) wired up:
    `MorphologyEntry`/`MorphologyRepository`/`SqliteMorphologyRepository`
    per spec §12.2's method set, `MorphologyTabContent` for the "الصرف"
    tab's horizontal word-card strip.
    Also found and finished an incomplete refactor from earlier in this
    same session: `MorphologyTabContent` (`lib/features/morphology/
    presentation/`) and `GrammarTabContent` (`lib/features/tafsir/
    presentation/grammar_tab_content.dart`) already existed as standalone
    files, but `ayah_context_sheet.dart` still had its own private
    `_MorphologyTabContent`/`_MorphologyWordCard`/`_GrammarTabContent`
    duplicates — and had kept receiving fixes (the RTL-alignment and
    300px-height fixes logged above) that never made it into the
    standalone copies, which the app didn't actually use anywhere. Same
    risk CLAUDE.md already flagged once for `QuranAyahText` ("rather than
    risking two copies silently diverging") — here they already had.
    Resolved by making the standalone files the one real copy (carrying
    forward the private versions' fixes, since those were the ones
    actually tested), switching `ayah_context_sheet.dart` to import and
    use them, and deleting the private duplicates (net -142 lines in that
    file, now 736).
    Also root-caused and fixed the pre-existing `test/
    morphology_tab_scroll_test.dart` failure flagged above as "left
    as-is" — it wasn't a drag-*distance* issue after all. Instrumented the
    underlying `ScrollPosition` directly: the test's `Offset(-2000, 0)`
    drag left the horizontal list's scroll offset at exactly `0.0` (never
    moved), while `Offset(2000, 0)` drove it straight to
    `maxScrollExtent`. For a `reverse: true` horizontal list, the drag
    direction that advances through higher indices is the mirror image of
    a normal list's convention — the test had that backwards, the widget
    itself was always correct. Fixed the sign; test now passes.
    `flutter analyze`/`flutter test`: both fully clean (0 issues, all
    tests passing) — first time both are clean simultaneously since
    Prompt 12 started. Verified visually on the Android emulator
    (`emulator-5554`, fresh debug build): Al-Fatiha 1:4 ("مالك يوم
    الدين") — "الصرف" tab shows correct root/lemma/stem for الدين (د ي ن)/
    يوم (ي و م)/مالك (م ل ك) with نوع الكلمة/الوسوم النحوية correctly
    dashed-out, "الإعراب" tab still shows the correct real i'rab text
    right-aligned — confirming the extracted widgets work identically to
    the private versions they replaced.
    Also deleted 19 stray `scratch_screen*.png` debug screenshots left in
    the repo root from this session's earlier on-device verification
    passes, and a stray 0-byte `raw_resources/word-lemma.db` left over
    from a mid-extraction interruption (both untracked/git-ignored
    clutter, not part of any deliverable).
  - **"التفسير" tab replaces "المعنى"** (2026-09-14, user's explicit
    request: "عاوزة التاب بتاعة المعني تستبدل بتاب التفسير اللي تحت ...
    يكون كلمة الاعراب والتفسير جنب بعض ... من غير الحاجة التالتة اللي
    هيا الاعراب الميسر") — a deliberate deviation from spec §10 (which
    lists Study tabs as "Meaning, Morphology, Grammar, Qiraat (future)"
    and Tafsir only as a bottom action), not an oversight. `StudyTab
    .meaning` renamed to `StudyTab.tafsir` (`quran_reader_provider.dart`);
    tab order/labels in `_StudyTabsRow` are now التفسير, الإعراب, الصرف,
    القراءات — Tafsir and Grammar adjacent, per the user's ask. New
    `_TafsirTabContent`/`_TafsirSourceSection`/`_TafsirSourceContent`
    widgets (`ayah_context_sheet.dart`) show the same already-ingested
    `TafsirRepository` sources the full-screen `TafsirScreen`/"تفسير"
    action already use (CLAUDE.md rule #4 — no second copy of the data or
    query logic) as a single-open accordion, first source expanded by
    default — but filtered to exclude `iraabMuyassarSourceId`, since that
    source is shown exclusively on the "الإعراب" tab instead. The now-
    dead `_StudyTabPlaceholder` class (every `StudyTab` value has real
    content now) was removed rather than left unreachable.
    `flutter analyze`/`flutter test`: clean (same one pre-existing
    failure as above, untouched by this change). Verified visually on the
    Pixel 6 API 34 emulator — booted headless this time (`-no-window
    -gpu swiftshader_indirect`) after the normal windowed boot kept
    getting torn down early in this session's sandboxed environment
    (`UpdateLayeredWindowIndirect failed ... device ... not functioning`
    in the emulator's own log — a display-subsystem issue in this
    session's environment, not the app): tab order/labels correct,
    التفسير opens by default on a fresh ayah selection with Ibn Kathir
    expanded, collapsing it reveals only "تفسير السعدي" underneath (no
    third "الإعراب الميسر" entry), expanding As-Saadi shows its own real
    content correctly right-aligned, and switching to "الإعراب" still
    shows the real i'rab text (both prior fixes above still intact).
  - **Ayah-end marker no longer gets a morphology card** (2026-09-14,
    user-reported: "الصرف" showed an extra rectangle for the ayah number,
    e.g. "٣", styled and laid out exactly like a real word's card). This
    is precisely the ayah-end ornament glyph the "Data blocker resolved"
    entry above already identified while cross-checking the ingestion —
    `words` legitimately carries it as one extra row per ayah (real Mushaf
    rendering requirement, rule #2), but `MorphologyTabContent` was
    iterating every `words` row with no way to tell it apart from a real
    word, so it got its own (empty) card.
    Fixed at the source per the user's explicit ask, not with a per-widget
    visual filter: `schema.dart`'s `words` table gained a `word_type`
    column ('word' | 'end_marker', same convention as `mushaf_lines
    .line_type`), computed once in `tool/ingest_quran_data.dart`'s
    `_buildWords` as the highest `word_position` in each ayah — the
    Word/domain model (`word.dart`) now exposes this as `Word.wordType`/
    `Word.isAyahEndMarker`, so any current or future word-level feature
    can filter on it without re-deriving the rule. Added a matching
    integrity check (`_runIntegrityChecks`) asserting exactly one
    'end_marker' per ayah, always at that ayah's own highest position —
    turning this session's one-time manual investigation into a
    permanent, enforced invariant rather than tribal knowledge.
    That investigation (before writing any fix) chased down what first
    looked like a real off-by-one in the Prompt 12 ingestion: 3 of 6236
    ayahs (2:275, 4:176, 13:5 — all famously long ayahs) have the QUL
    word-lemma resource attach a real lemma value to what is structurally
    the marker's own position. Verified this is an upstream anomaly in
    that resource, not a flaw in the "last position = marker" rule: an
    independent cross-check (83668 total `words` rows − 6236 markers =
    77432, matching the Quran's widely-cited ~77,430 total word count)
    and a manual re-read of 2:275's actual tail words (`... أَصْحَابُ
    النَّارِ هُمْ فِيهَا خَالِدُونَ`, 5 real words) both confirm the
    marker really is the last position; the lemma resource just
    mistakenly indexed "نَار" against it instead of leaving it blank. Left
    that resource's data untouched (rule #1's spirit — never invent/alter
    upstream data, same treatment as As-Saadi's placeholder rows from the
    Tafsir module) and derived `word_type` purely from `words`' own
    structure instead of trusting the morphology resources' position
    coverage, so this rare anomaly can't mis-tag a real word.
    `MorphologyTabContent` now filters `words.where((w) =>
    !w.isAyahEndMarker)` before building cards — one line, now backed by
    real schema knowledge instead of a guess. Added a second, targeted
    widget test (`test/morphology_tab_scroll_test.dart`) constructing a
    `Word` with `wordType: 'end_marker'` directly and asserting it gets no
    `MorphologyWordCard`; confirmed it's a real regression guard, not a
    tautology, by temporarily reverting the filter and watching the test
    fail (`findsNWidgets(3)` → "too many"), then restoring the fix and
    re-confirming green. `assets/database/quran.db` regenerated (word_type
    populated: 77432 'word' / 6236 'end_marker', matching the count
    above). `flutter analyze`/`flutter test`: clean throughout (3/3
    tests). Verified on the Android emulator with a fresh install (the
    on-device DB is only copied from the bundled asset on first run, so a
    plain reinstall over old app data wouldn't have picked up the
    regenerated `quran.db` — uninstalled first): Al-Fatiha 1:4's "الصرف"
    tab shows exactly 3 cards (مالك/يوم/الدين), no 4th marker card, and
    1:1's first 3 visible cards (الرحمن/الله/بسم) show no marker between
    or around them either — this session's emulator couldn't confirm the
    4th/5th positions past this point since `adb input swipe` doesn't
    reliably drive the horizontal drag gesture here (a pre-existing,
    already-documented environment limitation, not a code issue — see the
    Prompt 12 build-history entry above), which is exactly why the direct
    widget test above carries the real proof for this fix, not the
    on-device screenshots.
- [ ] Phase 3 — Bookmarks/notes/last-read, performance, validation suite

## Version control

This project is under git, remote `origin` →
https://github.com/EsteshhadMohammed36/quran_app.git, branch `main`.
Do **not** add a `Co-Authored-By: Claude ...` trailer to commit messages
(user preference — she doesn't want Claude listed as a GitHub contributor).
Write commit messages as if authored solely by the user.

## Working mode per task type

- Reading/analysis only → **Plan mode**.
- Touches Quran text, rendering, ayah resolution, or data ingestion →
  **Default mode** (ask before each edit) — review every change here.
- Pure scaffolding, UI-only, or non-religious app logic (bookmarks UI, perf
  tuning, test files) → **Auto-accept edits** is fine.
