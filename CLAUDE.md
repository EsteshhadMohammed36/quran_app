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
