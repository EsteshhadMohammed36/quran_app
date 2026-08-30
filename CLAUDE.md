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

- [ ] Phase 0 — Mushaf prototype validated (spec §25)
- [x] Phase 1 — Project structure + SQLite schema + resource manifest
  - [x] Project structure (`lib/core/*`, `lib/features/*/{data,domain,presentation}`) + deps (`provider`, `sqflite`, `path_provider`, `path`)
  - [x] SQLite schema (§15 tables + §15.1 indexes) — `lib/core/database/schema.dart` + `app_database.dart`
  - [x] Resource manifest bookkeeping (§16, §27) — `lib/core/resource_manifest/{resource_manifest_entry,resource_manifest_repository,sqlite_resource_manifest_repository}.dart`; `resource_manifest` table gained an `attribution_text` column (§27) not in the §16 list verbatim
  - [x] QUL resource download instructions — user downloaded 4 resources for the `madinah-v2-qpc-v2-hafs` group into `raw_resources/` (git-ignored): Mushaf layout (`qpc-v2-15-lines.db.zip`), Quran script (`qpc-v2.db.zip`), font (`QPC V2 Font.ttf.bz2`, actually a zip of 604 page fonts), surah names (`quran-metadata-surah-name.json.zip` — added mid-Prompt-6 once `surahs.name_arabic` turned out to have no source among the first 3; user chose the QUL fallback over quran-assets/metadata). Schemas verified by hand against spec §6/§8. Checksums + full metadata in `tool/resource_manifest_seed.dart`.
  - [x] Ingestion pipeline (§23/§23.1/§24) — `tool/ingest_quran_data.dart`: reads the 4 raw_resources files via the `sqlite3` CLI + `package:archive`, transforms to canonical schema, runs all §24 integrity checks, writes a fresh pre-populated `assets/database/quran.db` (114 surahs, 6236 ayahs, 83668 words, 9046 mushaf_lines, 4 resource_manifest rows — verified against live counts). `lib/core/database/app_database.dart` now copies this bundled asset to the documents dir on first run instead of on-device ingestion (user's explicit choice over in-app ingestion, 2026-08-30). `flutter analyze`/`dart analyze tool/`/`flutter test`: clean. Verified end-to-end on the Pixel 6 API 34 emulator (temporary debug print, reverted) — real device confirmed the asset-copy + query path works.
- [ ] Phase 2 — Ayah selection, context sheet, tafsir, morphology, audio
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
