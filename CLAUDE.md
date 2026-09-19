# Quran App — Project Rules

Flutter app: a Mushaf-first Quran reader with a contextual ayah study layer
(tafsir, morphology, grammar, audio, bookmarks/notes/last-read), built on
`quran-assets` + resources from the Quranic Universal Library (QUL).

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
   version, checksum, license/terms URL) — no exceptions. (spec §5, §16, §27)
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
              audio/  bookmarks/  notes/  last_read/  user_library/  search/
                (each feature: data/ domain/ presentation/)
  shared/     widgets/  theme/
```

UI widgets depend on domain interfaces (Repository classes), never on raw
QUL/SQLite rows directly. State management: Provider (spec §17.1).

## Current phase

Phase 0, 1, and 2 (prompts 9–13) are complete and validated. Phase 3's first
slice (Prompt 14) is complete and verified. Full narrative history of how
each prompt was built has been trimmed from this file (was 700+ lines of
now-resolved back-and-forth) — only the facts a future prompt actually needs
are kept below. Git history has the full story if needed.

- [x] **Phase 0 — Mushaf prototype** (spec §25). `MushafPageView` renders
  the fixed line structure (no reflow, rule #2) from `MushafLine.lineType`
  (`surah_name` / `basmallah` / `ayah`). Surah-header banner is a decorative
  per-surah ligature glyph (`surah_header_ligatures.dart`, QUL "surah header
  font", not the page-specific QCF font and not plain text) — full page
  width via `BoxFit.fill`, fixed height `screenHeight * (2/18)` (not a
  relative flex share — that would make Al-Fatiha's banner a different size
  than every other surah's, since it only has ~8 lines vs. the usual 15).
  Basmallah lines render Al-Fatiha 1:1's real words with the `QCF2001` font
  specifically (genuine Quran data, not invented text — rule #1). Theme:
  `lib/shared/theme/mushaf_theme.dart` (flat warm-white page, near-black
  ink — not the Flutter default seeded theme). Verified visually on pages
  1, 300, 601, 604.
- [x] **Phase 1 — schema + ingestion** (spec §15/§16/§23/§24). SQLite schema
  in `lib/core/database/schema.dart`; `app_database.dart` copies the
  pre-built `assets/database/quran.db` asset to the documents dir on first
  run (no on-device ingestion). `tool/ingest_quran_data.dart` is the single
  pipeline that rebuilds `quran.db` from everything in `raw_resources/`
  (git-ignored) — re-run it after adding/changing any raw resource, don't
  hand-edit the db. Every dataset it pulls in has a `resource_manifest` row
  seeded from `tool/resource_manifest_seed.dart` (rule #4). Base counts:
  114 surahs, 6236 ayahs, 83668 words, 9046 mushaf_lines.
- [x] **Phase 2 — ayah selection, context sheet, tafsir, morphology, audio**
  (Prompts 9–13, spec §9–§14):
  - Reader (`MushafReaderScreen`/`QuranReaderProvider`) lazily loads pages,
    caching only `currentPage ± 2` (rule #6). Word tap resolves
    `Word.ayahKey` (`surah:ayah`) and highlights the whole ayah, including
    across a Mushaf-line boundary. Hit-testing is one page-level
    `GestureDetector.onTapUp` + manual `TextPainter` lookup, **not**
    per-word `TapGestureRecognizer`s — avoids Flutter gesture-arena
    conflicts once both "tap a word" and "tap elsewhere dismisses" exist
    on the same page. All 604 QCF V2 page fonts are bundled (`assets/fonts/
    qpc_v2/`, family names `QCF2{page:03d}` read from each font's own
    `name` table, not guessed).
  - **`words.page_number` and `ayahs.page_number` are both always NULL** in
    the shipped `quran.db` (an ingestion gap, never fixed at the source —
    not urgent since nothing reads it). Anywhere a word/ayah's page is
    needed, derive it via `QuranRepository.getPageNumbersForWordIndexes()`
    (reads `mushaf_lines`' own `first_word_id`/`last_word_id` ranges
    instead). Used by the Ayah Context Sheet, `TafsirScreen`, and the Saved
    Items screen's jump-to-ayah.
  - `words.word_type` is `'word'` or `'end_marker'` — the last
    `word_position` in every ayah is the ayah-end ornament glyph, not a
    real word (needed for real Mushaf rendering, rule #2, but has no
    root/lemma/stem/audio segment). Any per-word UI (morphology cards, etc.)
    must filter `words.where((w) => !w.isAyahEndMarker)` first.
    `Word.isAyahEndMarker` exposes this on the domain model.
  - **Ayah Context Sheet** (`lib/features/ayah_study/presentation/
    ayah_context_sheet.dart`) is a persistent `Scaffold.bottomSheet` (not
    modal — the Mushaf page must stay visible/tappable around it, spec
    §10), toggled via `QuranReaderProvider.isAyahSheetOpen`. Capped at 80%
    of screen height with only the ayah-text+tabs+content region scrolling
    internally (header/actions/audio stay pinned) — a long tafsir/i'rab
    passage can otherwise overflow. Study tab order is **التفسير, الإعراب,
    الصرف, القراءات** — a deliberate deviation from spec §10 (user's
    explicit request): Tafsir replaced the "Meaning" tab and sits next to
    Grammar, instead of only being a bottom action. القراءات (Qiraat) stays
    disabled — spec marks it "(future)".
  - **Tafsir module**: 3 sources — Ibn Kathir, As-Saadi, Iraab Al-Muyassar
    (all Arabic, QUL). `tafsir_entries` stores real content only on a
    passage-group's first ("owning") ayah; member ayahs have `content =
    NULL` and `group_id` pointing at the owner — `SqliteTafsirRepository
    .getEntry` resolves this via a self-join so callers never see the raw
    shape. **"الصرف" tab = morphology (root/lemma/stem/POS), "الإعراب" tab
    = grammar/i'rab** — these two were mislabeled/swapped at one point in
    an earlier build; if study-tab content ever looks wrong, check this
    first. "الإعراب" reads the Iraab Al-Muyassar tafsir source directly via
    `TafsirRepository.getEntry` (`iraabMuyassarSourceId` constant) — it is
    *not* a separate dataset/table (rule #4). `TafsirScreen` (full-screen,
    opened via `Navigator.push`) takes `QuranReaderProvider` as an explicit
    constructor param, not ambient `context.read` — it isn't a descendant
    of the reader's own `ChangeNotifierProvider`. As-Saadi has 59 ayahs
    with genuinely no independent commentary + 4 rows holding only a
    placeholder symbol (upstream data quirk, kept verbatim per rule #1's
    spirit — not a bug to "fix").
  - **Morphology module**: root/lemma/stem populated from 3 QUL word-level
    resources; `part_of_speech`/`grammar_tags` are permanently `NULL` — no
    matching QUL resource exists for these (matches spec §12.2's "(when
    available)").
  - **Audio module**: one reciter (Mishari al-Afasy, Ayah-by-Ayah Murattal
    Hafs, with word segments). Audio is **streamed** via each ayah's
    `audio_url` at runtime (`just_audio` package) — not bundled, unlike the
    fonts (bandwidth). `audio_segments.segment_index` is the segment's own
    array position, not `word_position` (some ayahs legitimately repeat a
    phrase, so `word_position` isn't always unique per ayah); `word_key` is
    `null` on the ayah-end marker or a rare trailing segment.
    `AudioProvider` wraps one `just_audio` `AudioPlayer` and republishes the
    current segment's `word_key` for live highlighting.
- [x] **Bookmarks / Notes / Last Read** (Prompt 14, spec §15/§19/§26).
  Three new features (`bookmarks`, `notes`, `last_read`) each with the
  standard `data/domain/presentation` split, plus `user_library` holding
  `UserLibraryProvider` — one `ChangeNotifier` combining all three
  repositories with synchronous in-memory indexes (`isBookmarked`/
  `noteForAyah`) so the Ayah Context Sheet can check them on every build.
  - Reader restores the last page **and** ayah on launch by reading
    `ReadingStateRepository.getReadingState()` directly before the first
    frame (not via the provider's async load) — never falls back to page 1
    if a saved state exists (spec §19/§26).
  - Two independent writers share the one `reading_state` row: swiping
    pages auto-updates it (coarse, page-only, via `onPageChanged` →
    `UserLibraryProvider.updateLastReadPage`), while the sheet's "متابعة"
    action writes the precise surah:ayah (`markAyahAsLastRead`). This is
    by design — the coarse automatic write intentionally overwrites the
    precise one on the next page turn.
  - One permanent corner button (top-left, `Icons.bookmarks_outlined`)
    opens `SavedItemsScreen` — the *only* exception to the reader having no
    permanent chrome, since a bookmark/note nobody can revisit isn't
    useful. Jump-to-ayah reuses the `getPageNumbersForWordIndexes`
    workaround above (`ayahs.page_number` is NULL too).
  - `NoteRepository.upsertNote` enforces "at most one note per ayah"
    app-side (no DB uniqueness constraint on `ayah_key`).
  - **Verified end-to-end on-device (2026-09-18)** with direct SQLite
    proof pulled off the emulator, not just UI appearance: bookmark toggle,
    "متابعة"'s `reading_state` write, automatic last-read-on-page-swipe,
    and the Saved Items screen's list + jump-back-to-ayah all confirmed
    working. **Not** independently confirmed: actually typing and saving
    note text — see "Known environment issues" below (this is an emulator
    bug, not suspected app code; `SqliteNoteRepository` uses the identical
    proven pattern as the bookmark/reading-state repositories).
- [x] **Search module** (`lib/features/search`, spec §17's architecture
  tree — no numbered spec section of its own). `SearchScreen` is opened
  from a second permanent corner button (top-right, `Icons.search`, same
  opaque-chip treatment as the Saved Items button so it doesn't blend
  into the surah-header banner) — the reader's third deliberate exception
  to "no permanent chrome". `SearchRepository` has two separate methods
  (`searchAyahText`/`searchTafsir`), both plain SQL `LIKE` substring
  matches (same MVP scope as `TafsirRepository.search`: not full-text
  search/ranking).

  **`ayahs.text_uthmani` data-source bug found and fixed 2026-09-19**:
  it had been built (`_buildAyahs` in `tool/ingest_quran_data.dart`) by
  plain-space-joining `words.text` — but `words.text` is the QPC V2
  *glyph* script (page-specific presentation-form codepoints tied to the
  bundled Mushaf fonts, required for rendering, rule #2), not ordinary
  Arabic text — e.g. surah 55 ayah 1 was stored as literally two glyph
  codepoints, not the letters ا ل ر ح م ن. This meant `ayahs.text_uthmani`
  could never match anything typed on a real keyboard, for *any* query,
  diacritics or not — a data bug, not a matching bug. Fixed by sourcing
  `ayahs.text_uthmani` from a dedicated plain-Unicode Uthmani resource
  instead (QUL "Uthmani (Ayah by Ayah)", `qul-quran-script-uthmani-ayah-by-ayah`
  in `resource_manifest_seed.dart`, downloaded to
  `raw_resources/uthmani.db.zip` — rule #4). `words.text` (Mushaf
  rendering) is completely untouched by this fix, still the QPC V2
  glyphs it always was.

  **`searchAyahText` also folds tashkeel/tatweel/alef-variants on both
  sides of the match** (`SqliteSearchRepository._normalizeForMatch`,
  added 2026-09-19). Two real-keyboard-vs-canonical-orthography gaps,
  both needed even after the data-source fix above: (1) most users type
  queries without diacritics, but the real Uthmani text is always fully
  diacritized (tashkeel + Quranic annotation marks + a tatweel filler
  character, e.g. U+0640 sits *inside* "ٱلرَّحْمَـٰنُ" between م and
  ن); (2) Uthmani orthography spells certain letters with special alef
  variants in fixed positions (e.g. the "ال" definite article is always
  alef *wasla* ٱ, never plain ا) that a keyboard can't produce. Neither
  violates rule #1: normalization only ever touches a transient
  in-memory copy used to decide match/no-match — `ayahs.text_uthmani` in
  the database and the `snippet` returned to the UI are always the
  untouched canonical string, nothing stored or displayed is ever
  normalized. `searchTafsir` stays exact-match (tafsir prose isn't
  written in strict Uthmani orthography, so it didn't have either
  problem). **Verified on-device (2026-09-19, ADBKeyboard, fresh install
  + `pm clear` to force the corrected `quran.db` asset to re-copy)**:
  typing "الرحمن" with no diacritics (sheet closed, ayah-text scope)
  returned 10+ correctly-ordered real hits across Al-Fatiha, Al-Baqarah,
  Ar-Ra'd, Al-Isra, Maryam, etc., each snippet showing the untouched
  fully-diacritized canonical text; tapping a result jumped to Al-Fatiha
  1:1, highlighted the ayah on the Mushaf, and opened the Ayah Context
  Sheet on its default التفسير tab — same as before this fix. Before
  both fixes landed this same query returned "لا توجد نتائج" (confirmed
  on-device at each intermediate stage: glyph-data bug alone still
  returned nothing; data fix alone still returned nothing until the
  tashkeel/tatweel/alef folding was added too). `searchTafsir` spans every tafsir source at
  once (unlike the single-source-scoped search already on `TafsirScreen`)
  and tags each hit with its source name so a "الإعراب الميسر" hit isn't
  mistaken for general commentary. Selecting a result reuses the reader's
  existing `_jumpToAyah`.
  **`SearchScreen` is single-scope per instance, not a combined
  "search everything and group by kind" screen** — an earlier version did
  that (one screen searching both at once, results grouped under two
  headers); the user explicitly rejected it and asked for context-aware
  scoping instead: search the open Mushaf page's ayah text by default,
  but search tafsir instead whenever the Ayah Context Sheet's التفسير tab
  is the one currently open. `SearchScreen` itself stays unaware of *why*
  a scope was picked — it just takes a required `scope: SearchResultKind`
  constructor param (reusing the existing `ayahText`/`tafsir` enum rather
  than adding a duplicate one) and calls only the matching repository
  method, with the hint text/empty-state message worded per scope so
  it's unambiguous which thing is being searched. The scope decision
  itself lives in `MushafReaderScreen._openSearch`, which already owns
  `QuranReaderProvider` (the reader's own state — `isAyahSheetOpen` +
  `activeStudyTab == StudyTab.tafsir`) — chosen there specifically so
  `search` never has to import or read `quran_reader`'s presentation
  state; the composition root (`MushafReaderScreen`, which already wires
  together bookmarks/notes/tafsir/audio/user_library/search
  repositories) makes the call, consistent with every other cross-feature
  wiring in this file, not a new pattern. The corner button's tooltip
  itself reflects the resolved scope ("بحث في المصحف" / "بحث في
  التفسير") so it's clear before tapping which thing will be searched.
  As part of adding this module, the Ayah Context Sheet's Actions Row
  dropped its Tafsir button (kept only Note/Bookmark/Continue) —
  redundant once "التفسير" already sits as a first-class study tab,
  `tafsir_action_button.dart` deleted. That was the *only* thing that
  ever pushed the separate full-screen `TafsirScreen`
  (`lib/features/tafsir/presentation/tafsir_screen.dart`) — it's now
  unreachable/orphaned dead code (still analyzes clean since nothing
  references it incorrectly, just nothing references it at all). Leaving
  it in place for now since it's not otherwise in the way; worth either
  deleting it or wiring a new entry point to it in a future prompt rather
  than letting it silently bit-rot.
  **Verified on-device with real typed Arabic input** (2026-09-19, via
  ADBKeyboard — see "Known environment issues" below): with the sheet
  closed, search hint reads "ابحثي في آيات المصحف..." and a typed query
  returns only ayah-text hits; with the sheet open on التفسير, hint reads
  "ابحثي في التفسير..." and the same query ("الرحمن") returns 273
  tafsir-only hits, correctly labeled, no ayah-text section leaking in
  either direction. Tapping a result correctly jumps to that ayah and
  opens the Ayah Context Sheet with real content (always opens on the
  sheet's default التفسير tab regardless of which source the hit came
  from — `onResultTap` only carries `ayahKey`, not the matched source;
  acceptable MVP scope, not wired to auto-select a tab). Also confirmed:
  the arrow glyph in the app bar is Flutter's auto-inserted **back**
  button (mirrored for RTL, not a submit control — the real submit is
  the leading magnifying-glass `IconButton`, which sits on the visual
  left because `actions` mirrors in RTL).
- [x] **Surah Index** (`lib/features/quran_reader/presentation/
  surah_index_screen.dart`, added 2026-09-19 — not one of the original
  17 prompts; spec §3 lists "Surah, Juz, Hizb and page navigation" as
  in-scope but it was never broken out into its own prompt, and nothing
  built it until now). "فهرس السور" — a plain list of all 114 surahs by
  Arabic name, ayah count, and revelation place, tap-to-jump straight to
  that surah's opening Mushaf page. Kept inside `quran_reader`'s own
  `presentation/` rather than a new top-level feature — it needs nothing
  beyond `QuranRepository`/`Surah`, which already live there (rule #4: no
  new table, no new feature module for something the existing schema
  already answers). Two new `QuranRepository` methods back it:
  `getAllSurahs()` (plain `surahs` table read) and
  `getFirstPageNumbersForSurahs()`, which resolves each surah's opening
  page from `mushaf_lines.line_type == 'surah_name'`
  (`MIN(page_number) GROUP BY surah_number`) — confirmed via direct
  SQLite query that all 114 surahs have exactly one such line, so every
  surah always resolves (no NULL/missing page case to handle). This is a
  different, more direct derivation than `getPageNumbersForWordIndexes`
  (used elsewhere for a *specific ayah's* page): the surah's banner line
  itself already carries `page_number`, no word-index range lookup
  needed.
  Fourth (and last planned) deliberate exception to the reader's "no
  permanent chrome" rule, alongside Saved Items (top-left) and Search
  (top-right): a bottom-left opaque-chip corner button
  (`Icons.menu_book_outlined`, tooltip "فهرس السور") opens it. Tapping a
  row calls back to `MushafReaderScreen` (same pattern as
  `SavedItemsScreen`/`SearchScreen` — only it owns the `PageController`),
  which pops the screen and calls `_pageController.jumpToPage` directly;
  unlike `_jumpToAyah`, this never selects/highlights an ayah or opens
  the context sheet — it's pure page navigation, matching "jump to a
  surah" rather than "jump to a specific ayah".
  **Verified on-device (2026-09-19)**: fresh debug build installed on
  the emulator, screenshotted opening on Al-Fatiha (last-read restore
  still intact), tapped the new corner button, confirmed the index list's
  data against a direct SQLite query of the same `surahs`/`mushaf_lines`
  join (page numbers matched exactly — Al-Fatiḥah p1, Al-Baqarah p2, Āl
  ʿImrān p50, An-Nisāʾ p76, Al-Māʾidah p106), then tapped "البقرة" and
  confirmed the reader actually jumped to page 2's Al-Baqarah surah-name
  banner.
- [ ] Phase 3 remainder — performance pass, validation suite (not started).

## Known environment issues (this sandboxed dev machine)

Re-check these before assuming a new failure is a code bug — they've each
already cost a full debugging pass once:

- **Focusing a `TextField` crashes the headless emulator, 100% reproducible.**
  Confirmed 3× tapping `NoteEditorSheet`'s text field (IME/gfxstream
  interaction in this specific `-no-window -gpu swiftshader_indirect` boot
  config), unaffected by disabling all animations. Every *other* tap/swipe
  interaction on the same screens worked fine. If a UI feature needs text
  entry, expect this crash and verify via direct SQLite proof instead.
  **Not universal**: `SearchScreen`'s `autofocus: true` `TextField` (a
  plain `Scaffold` app-bar field, not `NoteEditorSheet`'s modal bottom
  sheet) focused fine with the keyboard shown, no crash — so the trigger
  is narrower than "any `TextField` focus"; still expect it might recur
  and verify via direct SQLite proof as a fallback.
- **`adb shell input text` cannot type Arabic/non-Latin text** — throws
  `java.lang.NullPointerException` in `InputShellCommand.sendText`
  (`KeyCharacterMap` can't map non-Latin chars to virtual key events).
  Device stays alive; this is an `adb` limitation, not an app crash. Two
  workarounds, in order of preference:
  1. **ADBKeyboard IME** (now installed on this AVD, 2026-09-19,
     `senzhk/ADBKeyBoard` — a ~17KB open-source IME whose only job is
     accepting Unicode over `adb`, from `https://raw.githubusercontent.com
     /senzhk/ADBKeyBoard/master/ADBKeyboard.apk`): once installed
     (`adb install ADBKeyboard.apk`) and selected as the active IME
     (`adb shell ime enable com.android.adbkeyboard/.AdbIME` then
     `adb shell ime set com.android.adbkeyboard/.AdbIME`), any focused
     text field accepts real Arabic via
     `adb shell am broadcast -a ADB_INPUT_TEXT --es msg 'عربي'` — types
     instantly, no on-screen keyboard needed. Verified end-to-end typing
     "الرحمن" into `SearchScreen` and getting real, correctly-grouped
     results (see Search module entry above). Switch back to
     `com.android.inputmethod.latin/.LatinIME` when done if a later
     verification pass needs the stock keyboard's own behavior.
  2. **Direct SQLite proof** (no install needed, use when ADBKeyboard
     isn't set up yet or the feature under test doesn't route through a
     visible `TextField`): pull the on-device db and run the same query
     with a substring taken straight from the stored data itself
     (`SELECT ... WHERE col LIKE '%' || (SELECT substr(...) FROM ...) ||
     '%'`) — sidesteps typing entirely while still proving the real
     `LIKE`/query logic against real data. This is how the Notes feature
     (Prompt 14) and this Search module's SQL layer were first verified,
     before ADBKeyboard existed on this AVD.
- **`adb input tap`/`swipe` can degrade or the whole emulator process can
  vanish mid-session**, unrelated to the app. Always run `adb devices`
  after a tap/swipe to confirm the device is still there before trusting a
  screenshot.
- **Headless boot is more stable than windowed** in this environment:
  `emulator -avd Pixel_6_API_34 -no-window -gpu swiftshader_indirect
  -no-snapshot-load` (windowed boot has failed with
  `UpdateLayeredWindowIndirect` errors before).
- **After any emulator restart, rebuild before reinstalling.** A stale
  pre-built `.apk` already sitting in `build/app/outputs/flutter-apk/` can
  get silently picked up by `flutter install`/`adb install -r` without
  reflecting current source — confirm with `flutter build apk --debug`
  (or `flutter run`) fresh each time, not just `flutter install`.
- **`android/gradle.properties` needs `kotlin.incremental=false`** — a
  Windows-specific Kotlin incremental-compiler bug fires when the project
  (`D:\...`) and the pub cache (`C:\Users\...`) are on different drive
  letters. Already set; don't remove it.
- **Git Bash + `adb`**: prefix commands with `MSYS_NO_PATHCONV=1` or
  absolute-looking paths (`/sdcard/...`) get mangled into Windows paths.
  Pull the on-device app database with
  `adb exec-out run-as com.example.quran_app cat <path> > local_file`
  (not `adb shell run-as`, which doesn't work for binary files here).
- `path_provider_android` must stay pinned via `dependency_overrides` in
  `pubspec.yaml` (unrelated resolution issue on this setup).

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
