QURAN APP
Technical Product & Engineering Specification
Flutter implementation using quran-assets + QUL
Version 1.0 — Implementation-ready handoff

Purpose: This document is the implementation contract for the engineer building the Quran reading/study experience. It defines what to use from quran-assets and Quranic Universal Library (QUL), how to structure the data, how the Mushaf renderer must work, how ayah selection works, how Tafsir/Morphology/Audio are connected, and what must be tested before the feature set is considered complete.
# 1. Executive Decision
Area
Decision
Priority
Existing Quran assets
Keep quran-assets. Do not replace it wholesale.
P0
Page-accurate Mushaf
Use a compatible Mushaf Layout + Quran Script + Font stack.
P0
Primary Mushaf candidate
KFGQPC/Madinah V2 1421H-style, 604 pages / 15 lines / Hafs.
P0
Word-level identification
Use QPC V2 Glyph Word-by-Word or the exact compatible script for the chosen layout/font.
P0
Database
Local SQLite for query-heavy datasets; bundle fonts/assets separately.
P0
Ayah selection
Hit-test word-level content, resolve selected word to surah:ayah, then select the whole ayah.
P0
Tafsir
Use QUL Tafsir resources where they add coverage/structure; avoid duplicate copies already present in quran-assets.
P0
Morphology
Use QUL word-level morphology for root/lemma/stem/POS/grammar tags where needed.
P1
Recitation
Keep existing audio where sufficient; add QUL segments when synchronized highlighting is required.
P0/P1
quran-ttx
Do not add by default. Use only if the selected rendering stack needs it after prototype validation.
P2/conditional

Important: QUL is a downloadable resource library. Its documentation currently states that you generally do not need to clone or run QUL locally; you download datasets and integrate them into your own app/workflow. The API is listed separately as coming soon. Source: QUL Download Resources documentation.
# 2. Official Sources — Use These as the Source of Truth
QUL Download Resources: https://qul.tarteel.ai/docs/download-resources
QUL Downloading & Using Data: https://qul.tarteel.ai/docs/downloading-data
QUL Data Model: https://qul.tarteel.ai/docs/data-model
QUL Mushaf Layout: https://qul.tarteel.ai/docs/mushaf-layout
QUL Mushaf Layout End-to-End: https://qul.tarteel.ai/docs/tutorial-mushaf-layout-end-to-end
QUL Mushaf Layouts Directory: https://qul.tarteel.ai/mushaf_layouts
QPC V2 Glyph — Word by Word: https://qul.tarteel.ai/resources/quran-script/61
QPC V2 Font: https://qul.tarteel.ai/resources/font/249
QUL Font Directory: https://qul.tarteel.ai/resources/font
QUL Tafsir Directory: https://qul.tarteel.ai/resources/tafsir
QUL Morphology End-to-End: https://qul.tarteel.ai/docs/tutorial-morphology-end-to-end
QUL Morphology Resources: https://qul.tarteel.ai/resources/morphology
QUL Recitation End-to-End: https://qul.tarteel.ai/docs/tutorial-recitation-end-to-end
QUL Recitation Resources: https://qul.tarteel.ai/resources/recitation
Tarteel quran-assets: https://github.com/TarteelAI/quran-assets
Tarteel quran-ttx: https://github.com/TarteelAI/quran-ttx/tree/main
# 3. Product Scope
The app is not only a Quran text viewer. It is a Mushaf-first reader with a contextual ayah study layer.
Mushaf page reading with a page-accurate layout.
Surah, Juz, Hizb and page navigation.
Ayah selection by tapping the rendered Quran content.
Contextual bottom sheet for the selected ayah.
Quick study tabs: meaning, morphology, grammar and future Qira'at.
Full Tafsir reader with multiple Tafsir sources in collapsible sections.
Ayah audio playback with optional synchronized highlighting.
Bookmarks, notes and last-read position.
Offline-first reading and local querying.
# 4. High-Level Architecture
Flutter UI   │   ├── Quran Reader   │     ├── Mushaf Renderer   │     ├── Page Navigation   │     └── Ayah Selection Controller   │   ├── Ayah Study Layer   │     ├── Meaning   │     ├── Morphology   │     ├── Grammar   │     ├── Tafsir   │     └── Audio   │   └── User Layer         ├── Bookmarks         ├── Notes         ├── Last Read         └── Preferences            │            ▼     Repositories / Domain            │            ▼      Local SQLite + Assets            ▲            │   ┌────────┴─────────┐   │                  │quran-assets        QUL(existing)      (missing/advanced)   │   └── quran-ttx only if required by rendering validation
Do not let the presentation layer read raw QUL files directly. Normalize/validate resources first, then expose a stable repository interface.
# 5. Source-of-Truth Strategy
Use a canonical-source approach. Each feature should have exactly one production source after validation. If quran-assets already provides an equivalent resource that is complete and suitable, keep it. Pull from QUL only when it fills a gap, provides the needed structure, or is the chosen compatible rendering resource.
Feature
Primary candidate
Fallback / comparison
Rule
Quran text
quran-assets
QUL Quran Script
Do not duplicate canonical text unless required for rendering.
Mushaf layout
QUL
quran-assets pages
Prefer QUL if using a QUL-compatible layout/script/font stack.
Quran script
QUL QPC V2 Word-by-Word
quran-assets scripts
Must match the selected font/layout.
Quran font
QUL QPC V2 Font
quran-ttx / quran-assets fonts
Use only with a compatible script.
Metadata
quran-assets
QUL metadata
Choose the cleaner, more complete schema.
Tafsir
Existing quran-assets where sufficient
QUL Tafsir
Avoid duplicated large text fields.
Morphology
QUL
Existing project data if present
Word-level joins required.
Audio
Existing quran-assets where sufficient
QUL recitation/segments
Use QUL when timing segments are needed.
Translations
Existing quran-assets
QUL
Only add what product needs.

# 6. Mushaf Rendering Requirements
QUL explicitly defines Mushaf Layout as structured page data and states that rendering requires: (1) word-by-word Quran script, (2) a compatible font, (3) selected Mushaf layout data, and (4) Surah names from Quran metadata. This stack is the foundation of the page-accurate reader.
Resource
Required fields / role
Implementation
Mushaf Layout
page_number, line_number, line_type, is_centered, first_word_id, last_word_id, surah_number
Render page line-by-line.
Quran Script
word_index/word position, text, word_key/location, surah, ayah
Resolve words in exact order.
Font
Font family / page font / ligatures
Render the QPC glyph text correctly.
Surah names
Surah ID -> Arabic name
Render surah_name lines.
Basmallah
Line type = basmallah
Render designated Bismillah line.

QUL's Mushaf Layout documentation defines the `pages` table with line-level fields and explains that an `ayah` line should retrieve words between `first_word_id` and `last_word_id` and render them in order. It also distinguishes `surah_name` and `basmallah` line types. Source: QUL Mushaf Layout documentation.
## 6.1 Recommended Primary Layout
Start the prototype with the KFGQPC V2 / Madinah 1421H-style 15-line Hafs layout. QUL's current layout directory lists a 604-page, 15-line Hafs layout for this family. Do not assume that every layout can use every font/script resource; verify compatibility.
Layout directory: https://qul.tarteel.ai/mushaf_layouts
## 6.2 Renderer Pipeline
loadPage(pageNumber)  -> query layout.pages ORDER BY line_number  -> for each line:       if line_type == "surah_name":           resolve surah_number -> surah name           render surah header       if line_type == "basmallah":           render Bismillah       if line_type == "ayah":           query words where word_index BETWEEN first_word_id AND last_word_id           order by word_index           render with selected Quran font           create hit targets for each word  -> expose semantic Ayah IDs for interaction
## 6.3 Critical Rendering Rule
Do not build the primary Mushaf page with a normal paragraph that wraps automatically based on device width. The page geometry is part of the product. The renderer must respect the line structure supplied by the selected Mushaf Layout.
Responsive behavior should scale the page/typography as a controlled Mushaf surface, rather than reflowing the Quran into an arbitrary paragraph layout.
# 7. Font Requirements
The first font candidate is QPC V2 Font. The official QUL resource describes QPC V2 as a Quran page-by-page font resource and provides font integration details. Standard Quran fonts require a matching Quran script; special surah/Juz fonts can additionally depend on ligatures.
QPC V2 Font: https://qul.tarteel.ai/resources/font/249
The official QPC V2 resource uses `p1-v2`/page-specific naming conventions in its integration example and the QPC V2 script resource uses a matching font-family metadata pattern. The engineer must use the exact family names included with the downloaded font package rather than hard-code a guessed family.
Flutter-specific requirement: create a minimal proof-of-rendering on the target platforms before committing the full reader. The QUL page documents CSS/HTML integration directly; Flutter must be validated separately for font loading, glyph shaping, ligatures and performance.
# 8. Quran Script Requirements
Use the QPC V2 Glyph Word-by-Word resource as the first candidate when paired with the compatible QPC V2 rendering stack. Its records include `verse_key`, `text`, `script_type`, `font_family`, `words[]`, `position`, `word text`, `location`, `page_number`, `juz_number` and `hizb_number`.
QPC V2 Word-by-Word: https://qul.tarteel.ai/resources/quran-script/61
Ayah key:27:82Word key:27:82:127:82:227:82:3...
The `location` pattern is the core key for word-level study features. Use numeric IDs in the database where possible, while preserving the canonical location string for interoperability.
# 9. Ayah Selection / Tap Interaction
This is a product requirement, not a QUL feature that should be assumed to exist automatically. We build it on top of word-level script and Mushaf layout data.
Tap on a rendered Quran word    -> identify word target    -> resolve word key = surah:ayah:word    -> derive ayah key = surah:ayah    -> mark selectedAyah    -> highlight all words belonging to that ayah    -> open Ayah Context Sheet
Selection must be semantic at ayah level. A tap on any word belonging to the selected ayah must select the entire ayah, not only the tapped word.
## 9.1 Selection States
State
Behavior
Idle
No ayah selected; pure reading.
Selected
Selected ayah highlighted and context sheet visible.
Study tab active
Selected ayah remains stable while content changes.
Tafsir open
Tafsir reader replaces/extends the context layer without losing ayah identity.
Different ayah tapped
Selected ayah changes in place; sheet remains open when practical.
Outside tap
Dismiss selection/sheet according to UX rules.

# 10. Ayah Context Sheet
AyahContextSheet ├── Header │    ├── Surah name │    ├── Ayah number │    └── Share │ ├── Selected Ayah │ ├── Study tabs │    ├── Meaning │    ├── Morphology │    ├── Grammar │    └── Qiraat (future) │ ├── Actions │    ├── Tafsir │    ├── Note │    ├── Bookmark │    └── Continue / Last-read │ └── Audio      ├── Play/Pause      ├── Reciter      └── Optional synchronized highlight
The visual reference shows a compact contextual panel rather than navigating away on every ayah tap. Preserve the Quran page context and keep the selected ayah as the central state.
# 11. Tafsir Module
QUL provides a large catalog of Tafsir resources and downloadable resource formats. The app should load only the sources selected for the product. Start with a small Arabic set and expand later.
QUL Tafsir directory: https://qul.tarteel.ai/resources/tafsir
Recommended initial sources for the reference UX: Ibn Kathir, As-Saadi, and an Arabic grammar/explanation source where licensing and resource metadata permit. Exact source choice must be confirmed against the resource detail page and terms before release.
The Tafsir data model must support grouped/continued tafsir entries. Do not assume every `surah:ayah` has an independent text blob. Preserve group references where present.
## 11.1 Tafsir UI
TafsirScreen  -> Selected Ayah header  -> List of Tafsir Sources       -> Accordion Source Header       -> Source Content  -> Previous / Current / Next Ayah navigation  -> Font size control  -> Search control  -> Return to Mushaf
## 11.2 Tafsir API inside the app
TafsirRepository  getSources()  getEntry(sourceId, ayahKey)  getGroup(sourceId, ayahKey)  search(sourceId, query)
# 12. Morphology Module
QUL's morphology documentation is explicitly word-level and intended for tap-word grammar insights, root/lemma search and Arabic linguistic study tools. Typical fields include word location, root, lemma/stem, part-of-speech and grammar tags.
QUL Morphology: https://qul.tarteel.ai/docs/tutorial-morphology-end-to-end
Morphology resources: https://qul.tarteel.ai/resources/morphology
## 12.1 Data key
morphology key= surah + ayah + word_positionExample:27:82:4
## 12.2 Morphology UI
Tap selected ayah -> Morphology tab -> show word list / analysis -> show:      Word      Root      Lemma      Stem      Part of Speech      Grammar tags (when available)
# 13. Grammar / I'rab Module
Keep grammar analysis separate from Tafsir and separate from morphology. Morphology is primarily word-form/linguistic metadata; grammar is syntactic/grammatical analysis. The data source used must be identified explicitly in the app's resource manifest.
Do not label a generic morphological POS tag as 'إعراب' unless the selected resource actually provides the grammatical analysis the product promises.
# 14. Recitation / Audio
QUL recitation resources can provide surah-by-surah audio, ayah-by-ayah audio, and segment timing arrays used for synchronized word or ayah highlighting. Use this only where it improves the existing quran-assets audio layer.
Recitation tutorial: https://qul.tarteel.ai/docs/tutorial-recitation-end-to-end
Recitation resources: https://qul.tarteel.ai/resources/recitation
AudioController  currentReciter  currentAyah  currentWord  isPlaying  position  duration  segments[]On playback progress:  -> resolve current segment  -> map to word/ayah  -> update highlight state
For production, do not assume that a shared upstream CDN is the application's long-term storage strategy. Download/host required audio assets according to the resource's permitted terms and your own deployment plan.
# 15. Local Database Strategy
Use SQLite for query-heavy Quran study data and keep fonts/audio/binary assets outside the main relational tables.
Table
Purpose
Key
surahs
Surah metadata
surah_id
ayahs
Ayah metadata/text
(surah_id, ayah_number)
words
Word-level Quran script
(surah_id, ayah_number, word_position)
mushaf_lines
Page line structure
(page_number, line_number)
tafsir_sources
Source registry
source_id
tafsir_entries
Tafsir content/groups
(source_id, ayah/group key)
morphology
Word linguistic metadata
(surah_id, ayah_number, word_position)
audio_assets
Reciter/file metadata
audio_id
audio_segments
Timing metadata
(audio_id, segment index)
resource_manifest
Version/license/source tracking
resource_id
bookmarks
User bookmarks
(user_id, ayah_key)
notes
User notes
note_id
reading_state
Last read position
user_id

## 15.1 Required indexes
CREATE INDEX idx_ayahON ayahs(surah_id, ayah_number);CREATE INDEX idx_wordsON words(surah_id, ayah_number, word_position);CREATE INDEX idx_mushaf_linesON mushaf_lines(page_number, line_number);CREATE INDEX idx_tafsirON tafsir_entries(source_id, ayah_key);CREATE INDEX idx_morphologyON morphology(surah_id, ayah_number, word_position);
These joins/indexes follow the identifier guidance in the QUL data-model documentation.
# 16. Resource Manifest — Mandatory
Every imported dataset must have a manifest entry. This prevents silent duplication and makes future updates auditable.
resource_idresource_nameprovidercategorysource_urldownload_formatversion_or_revisionretrieved_atlicense_or_terms_urlsha256target_table_or_asset_pathcompatibility_groupstatus
Example compatibility_group for the first Mushaf prototype: `madinah-v2-qpc-v2-hafs`.
# 17. Flutter Architecture
lib/  core/    database/    assets/    resource_manifest/    errors/  features/    quran_reader/      data/      domain/      presentation/    ayah_study/      data/      domain/      presentation/    tafsir/    morphology/    audio/    bookmarks/    notes/    search/  shared/    widgets/    theme/
Target architecture assumes Flutter with a repository/service layer and Provider for app state. The core rule is that UI widgets should depend on domain interfaces, not raw QUL JSON/SQLite schemas.
## 17.1 Providers
QuranReaderProvider  currentPage  currentSurah  currentAyah  selectedAyahKey  isAyahSheetOpen  activeStudyTabTafsirProvider  sources  selectedSource  expandedSources  currentAyahAudioProvider  reciter  isPlaying  position  currentAyah  currentWord  segmentsUserLibraryProvider  bookmarks  notes  lastRead
# 18. Repository Interfaces
abstract class QuranRepository {  Future<Surah> getSurah(int surahId);  Future<Ayah> getAyah(String ayahKey);  Future<MushafPage> getPage(int pageNumber);  Future<List<Word>> getWords(String ayahKey);  Future<List<Word>> getWordsForPage(int pageNumber);}abstract class TafsirRepository {  Future<List<TafsirSource>> getSources();  Future<TafsirEntry?> getEntry(String sourceId, String ayahKey);}abstract class MorphologyRepository {  Future<WordAnalysis?> getWordAnalysis(String wordKey);}abstract class AudioRepository {  Future<List<Reciter>> getReciters();  Future<AudioTrack?> getAyahAudio(String reciterId, String ayahKey);  Future<List<AudioSegment>> getSegments(String reciterId, String ayahKey);}
# 19. UI / UX Acceptance Requirements
Mushaf page must preserve the selected layout's line structure and not arbitrarily reflow Quran text.
A tap on any Quran word must resolve to the correct surah:ayah identifier.
Selecting an ayah must visually highlight the whole ayah, not a single word only.
The selected ayah context sheet must expose the selected surah/ayah identity.
The context sheet must support audio, meaning, morphology, grammar and Tafsir entry points according to the implemented phase.
Opening Tafsir must preserve selected ayah identity and allow previous/current/next ayah navigation.
Tafsir sources must be collapsible and sourced by a stable resource ID.
Bookmarks and notes must be attached to ayah identity, not page pixels.
Last-read state must restore the reader to the saved location without returning to page 1.
The main Quran reading experience must work offline after the required assets/data are installed.
Resource versions and licenses/terms must be traceable in the resource manifest.
# 20. Loading, Empty and Error States
Situation
Required behavior
Tafsir not loaded
Show non-blocking loading state; keep Quran page usable.
Tafsir unavailable
Show retry/error state; do not crash reader.
Audio missing
Show unavailable state and keep study features usable.
Font failed to load
Fail clearly in dev/QA; never silently substitute a generic Arabic font for production Mushaf.
Mushaf page missing
Show controlled error state with page identifier.
Database migration failure
Fail safely; preserve previous DB until new DB passes validation.

# 21. Performance Requirements
Do not load all 604 pages' rendered widgets simultaneously.
Use lazy page loading and cache a small number of nearby pages.
Do not duplicate large Tafsir strings in memory unnecessarily.
Cache fonts/resources according to the selected renderer's needs.
Use SQLite indexes for repeated lookups.
Audio playback should not block the Mushaf UI thread.
Ayah selection/hit testing must remain responsive while scrolling.
# 22. Quran Content Integrity
This application handles religious source text. Treat source data as immutable production content. Do not 'clean up', normalize, auto-correct, spell-check, transliterate, or pass Quran script through transformations that can change characters or diacritics.
Never run generic Arabic text normalization over canonical Quran script.
Preserve the exact script variant required by the selected Mushaf resource.
Store source version and checksum for imported Quran resources.
Validate ayah counts and key consistency before shipping.
Keep resource-provider and licensing metadata with every non-public dataset.
Any replacement of the canonical Quran text requires explicit review and regression comparison.
# 23. Data Ingestion Pipeline
1. Select resource2. Download JSON/SQLite/font/audio package3. Record resource manifest metadata4. Verify checksum5. Inspect schema6. Validate identifiers7. Normalize field names8. Import into staging DB9. Run integrity checks10. Promote to production DB/assets11. Run Mushaf renderer tests12. Run Tafsir/Morphology/Audio integration tests
## 23.1 Naming normalization
Normalize field names internally to a single convention. Recommended canonical names: `surah_id`, `ayah_number`, `word_position`, `ayah_key`, `word_key`. Keep a source-field mapping in import code so upstream changes do not leak into the application layer.
# 24. Automated Validation Suite
Quran integrity:- 114 surahs present- expected ayah counts per surah- no duplicate (surah_id, ayah_number)- no orphan words- no invalid word positionsMushaf layout:- page numbers within selected layout range- line numbers unique per page- first_word_id <= last_word_id- all referenced words exist- all line_type values are supported- surah_name lines have valid surah_numberTafsir:- source IDs unique- ayah/group references valid- no broken group referencesMorphology:- every morphology row maps to a valid word keyAudio:- every file/segment references a valid reciter and ayah- segment ranges are non-negative
# 25. Mandatory Prototype Before Full Build
Do not build the entire app before validating the Mushaf rendering stack. Create a tiny proof-of-concept first.
Install the selected QUL Mushaf Layout.
Install the compatible QPC V2 Word-by-Word script.
Install the compatible QPC V2 font package.
Render page 1.
Render a page containing multiple Surahs/headers if the layout requires it.
Render a mid-range page.
Render page 604.
Tap individual words and log their word keys.
Resolve each tapped word to the correct ayah.
Highlight the complete ayah.
Open and close the context sheet.
Change selected ayah without losing the current page.
Prototype acceptance: no missing glyphs, no incorrect word order, no wrong ayah mapping, no unexpected line reflow, and stable interaction across supported target devices.
# 26. Mandatory Test Cases
Test
Expected result
First page
Page 1 renders correctly, including Surah name and Basmallah behavior.
Mid page
All lines render with correct order and alignment.
Boundary ayah
An ayah that starts/ends across layout lines remains selectable as one ayah.
Page boundary
An ayah on a page boundary still maps correctly.
Surah header
Surah name line uses correct surah metadata.
Selection
Tapping any word selects the parent ayah.
Selection switch
Tapping another ayah changes selection without corrupting state.
Tafsir
Correct Tafsir entry/group resolves for selected ayah.
Morphology
Correct analysis resolves for tapped word.
Audio
Correct audio plays for selected ayah.
Audio sync
Segments map to correct word/ayah when enabled.
Bookmark
Bookmark persists for the correct ayah.
Note
Note persists for the correct ayah.
Last read
Last page/ayah is restored after app restart.
Offline
Core Quran reading works with network disabled.

# 27. Licensing and Attribution — Mandatory Release Gate
Every downloaded resource must be checked against its own resource detail page, terms and license metadata before production redistribution. Do not assume that because a dataset is accessible from QUL it automatically has identical redistribution terms to every other dataset.
Store source URL and license/terms URL in the resource manifest.
Record version/revision and retrieval date.
Record attribution text required by the provider/resource.
For fonts, check font-specific terms.
For Tafsir text, check the source's rights/terms.
For audio, check the reciter/resource terms before hosting.
QUL Terms: https://www.tarteel.ai/terms
QUL resources directory: https://qul.tarteel.ai/resources
# 28. quran-assets Integration Notes
The existing Tarteel quran-assets repository currently exposes folders for audio, Indopak word-by-word, language models, metadata, pages, scripts, tafsir, text and translations. Use it as an existing asset source and compare each category with the QUL resources before importing duplicates.
quran-assets: https://github.com/TarteelAI/quran-assets
# 29. quran-ttx Decision
quran-ttx is a repository of TTX copies of Mushaf page TTF font files. It is not the application's Quran data layer. Keep it out of the main architecture unless the rendering prototype demonstrates that it is needed for a specific font conversion/inspection workflow.
quran-ttx: https://github.com/TarteelAI/quran-ttx/tree/main
# 30. Definition of Done
Selected Mushaf layout renders correctly on supported Flutter targets.
Quran script and font are verified as a compatible pair.
Word-level hit testing resolves correct word keys.
Ayah selection resolves the entire ayah and updates all dependent features.
Tafsir is available through an expandable source UI.
Morphology resolves correct word-level analysis where enabled.
Audio plays for the selected ayah and optionally syncs segments.
Bookmarks, notes and last-read state persist.
The core reader works offline.
All imported resources have manifest metadata and verified source/terms.
Automated integrity tests pass.
Prototype comparison confirms the selected Mushaf pages are visually and structurally faithful.
# 31. Engineer Implementation Checklist
[ ] Inventory the current quran-assets checkout actually used by the project.
[ ] Map every existing asset to the product feature that consumes it.
[ ] Select one QUL Mushaf Layout for MVP.
[ ] Select its compatible Quran Script.
[ ] Select its compatible Font.
[ ] Download and verify all three.
[ ] Build the Mushaf renderer prototype.
[ ] Implement word hit testing.
[ ] Implement Ayah selection state.
[ ] Implement Ayah Context Sheet.
[ ] Implement Tafsir repository and accordion UI.
[ ] Implement Morphology repository and UI if enabled in MVP.
[ ] Integrate audio and segments.
[ ] Implement user data: notes, bookmarks, last read.
[ ] Add SQLite indexes.
[ ] Build integrity validation scripts.
[ ] Build offline-first startup/DB migration flow.
[ ] Complete license/attribution manifest.
[ ] Run full regression test suite.
# Appendix A — Official Resource Families to Review
Resource family
Official page
Why it matters
Mushaf Layout
https://qul.tarteel.ai/mushaf_layouts
Page/line structure for faithful Mushaf rendering.
Quran Script
https://qul.tarteel.ai/resources/quran-script
Word-level Quran text and identifiers.
Fonts
https://qul.tarteel.ai/resources/font
Compatible rendering fonts and special font resources.
Quran Metadata
https://qul.tarteel.ai/resources/quran-metadata
Surah/Juz/Hizb and navigation metadata.
Tafsir
https://qul.tarteel.ai/resources/tafsir
Interpretation sources.
Morphology
https://qul.tarteel.ai/resources/morphology
Word roots/lemmas/stems/POS/grammar tags.
Recitation
https://qul.tarteel.ai/resources/recitation
Audio and optional timing segments.
All resources
https://qul.tarteel.ai/resources
Resource catalog and downloads.

# Appendix B — Important QUL Facts Used in This Specification
QUL documentation says downloaded resources can be integrated into your own app without cloning/running QUL locally. (Download Resources)
Mushaf Layout is explicitly a rendering-structure resource and includes page/line/word-range information.
Rendering a Mushaf layout requires a compatible Quran script, font, layout data and Surah names.
QUL's shared identifiers are surah_id/surah, ayah_number/ayah and word_position/position.
Morphology joins are word-level: surah + ayah + word position.
Recitation resources can include surah audio, ayah audio and timing segments for synchronized highlighting.
quran-assets is an existing Tarteel asset repository with audio, metadata, pages, scripts, tafsir, text and translations.
quran-ttx is a font-focused repository of TTX copies of Mushaf page TTF files.
