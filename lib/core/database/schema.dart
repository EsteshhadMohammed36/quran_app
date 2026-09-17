/// SQLite schema definitions for the Quran app local database.
///
/// Source of truth: docs/spec.md
///   - Section 15   (Local Database Strategy — table list + purpose/key)
///   - Section 15.1 (Required indexes)
///   - Section 23.1 (Naming normalization — canonical field names)
///
/// Canonical field names used throughout (per §23.1): `surah_id`,
/// `ayah_number`, `word_position`, `ayah_key`, `word_key`. Upstream
/// quran-assets/QUL field names must be mapped to these at import time —
/// see the ingestion pipeline (§23) — never leaked into this schema.
///
/// This file only defines schema (CREATE TABLE / CREATE INDEX strings).
/// It contains no queries, no models, and no business logic.
library;

/// `surahs` — Surah metadata. Key: `surah_id`.
/// Required by §6 ("Surah names | Surah ID -> Arabic name") to resolve
/// surah_name lines when rendering the Mushaf.
const String createSurahsTable = '''
CREATE TABLE surahs (
  surah_id INTEGER PRIMARY KEY,
  name_arabic TEXT NOT NULL,
  name_english TEXT,
  name_transliteration TEXT,
  revelation_place TEXT,
  ayah_count INTEGER NOT NULL
);
''';

/// `ayahs` — Ayah metadata/text. Key: `(surah_id, ayah_number)`.
/// `text_uthmani` is canonical Quran text — never transform it (§22).
const String createAyahsTable = '''
CREATE TABLE ayahs (
  surah_id INTEGER NOT NULL,
  ayah_number INTEGER NOT NULL,
  ayah_key TEXT NOT NULL UNIQUE,
  text_uthmani TEXT NOT NULL,
  page_number INTEGER,
  juz_number INTEGER,
  hizb_number INTEGER,
  PRIMARY KEY (surah_id, ayah_number),
  FOREIGN KEY (surah_id) REFERENCES surahs (surah_id)
);
''';

/// `words` — Word-level Quran script. Key: `(surah_id, ayah_number, word_position)`.
/// `word_index` is the global ordinal used by the Mushaf renderer pipeline
/// (§6.2: "query words where word_index BETWEEN first_word_id AND last_word_id").
/// `text` is canonical QPC glyph text — never transform it (§22).
/// `word_type` is one of: 'word' | 'end_marker' — same convention as
/// `mushaf_lines.line_type`. The qpc-v2 script resource stores the ayah-end
/// ornament (the circled ayah number every ayah ends with) as one extra
/// "word" row per ayah, always at the highest `word_position` — a real
/// rendering requirement (rule #2: the Mushaf line must show it), but not a
/// real Quran word, and it must never be treated as one for word-level
/// linguistic features (found via Prompt 12's Morphology tab wrongly giving
/// it a morphology card, spec §12). Computed once at ingestion time
/// (`tool/ingest_quran_data.dart`'s `_buildWords`) as the last position per
/// ayah, so every feature that needs "real words only" filters on this
/// column instead of re-deriving the same position-based rule itself.
const String createWordsTable = '''
CREATE TABLE words (
  surah_id INTEGER NOT NULL,
  ayah_number INTEGER NOT NULL,
  word_position INTEGER NOT NULL,
  word_key TEXT NOT NULL UNIQUE,
  word_index INTEGER NOT NULL UNIQUE,
  text TEXT NOT NULL,
  word_type TEXT NOT NULL DEFAULT 'word',
  page_number INTEGER,
  juz_number INTEGER,
  hizb_number INTEGER,
  PRIMARY KEY (surah_id, ayah_number, word_position),
  FOREIGN KEY (surah_id, ayah_number) REFERENCES ayahs (surah_id, ayah_number)
);
''';

/// `mushaf_lines` — Page line structure. Key: `(page_number, line_number)`.
/// Fields per §6 (Mushaf Rendering Requirements) / §6.2 (Renderer Pipeline).
/// `line_type` is one of: 'ayah' | 'surah_name' | 'basmallah'.
/// `is_centered` and boolean-shaped fields are stored as INTEGER 0/1
/// (SQLite has no native boolean type).
const String createMushafLinesTable = '''
CREATE TABLE mushaf_lines (
  page_number INTEGER NOT NULL,
  line_number INTEGER NOT NULL,
  line_type TEXT NOT NULL,
  is_centered INTEGER NOT NULL DEFAULT 0,
  first_word_id INTEGER,
  last_word_id INTEGER,
  surah_number INTEGER,
  PRIMARY KEY (page_number, line_number),
  FOREIGN KEY (surah_number) REFERENCES surahs (surah_id)
);
''';

/// `tafsir_sources` — Source registry. Key: `source_id`.
const String createTafsirSourcesTable = '''
CREATE TABLE tafsir_sources (
  source_id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  language TEXT,
  author TEXT
);
''';

/// `tafsir_entries` — Tafsir content/groups. Key: `(source_id, ayah_key)`.
///
/// Verified directly against the 3 downloaded QUL tafsir resources (Ibn
/// Kathir, As-Saadi, Iraab Al-Muyassar — Arabic, Prompt 11, spec §11):
/// every source gives exactly one row per ayah, but a *group* of
/// consecutive ayahs sharing one tafsir passage stores the real text only
/// on the group's first ("owning") ayah — every other ayah in that group
/// has its own row with `content` left NULL and `group_id` pointing back
/// to the owner's `ayah_key` (§11: "Do not assume every surah:ayah has an
/// independent text blob. Preserve group references where present.").
/// `group_id` equals `ayah_key` itself for a standalone (non-grouped)
/// entry — every row belongs to "a group", just one of size 1 in that
/// case, so callers never need to special-case "no group".
/// `group_ayah_start`/`group_ayah_end` are copied onto *every* row in a
/// group (owner and members alike) so a single row lookup already tells
/// you the full ayah range, with no second query needed just to display
/// e.g. "tafsir for ayahs 2:8-2:9".
const String createTafsirEntriesTable = '''
CREATE TABLE tafsir_entries (
  source_id TEXT NOT NULL,
  surah_id INTEGER NOT NULL,
  ayah_number INTEGER NOT NULL,
  ayah_key TEXT NOT NULL,
  group_id TEXT NOT NULL,
  group_ayah_start TEXT NOT NULL,
  group_ayah_end TEXT NOT NULL,
  content TEXT,
  PRIMARY KEY (source_id, ayah_key),
  FOREIGN KEY (source_id) REFERENCES tafsir_sources (source_id),
  FOREIGN KEY (surah_id, ayah_number) REFERENCES ayahs (surah_id, ayah_number)
);
''';

/// `morphology` — Word linguistic metadata. Key: `(surah_id, ayah_number, word_position)`.
/// Per §12.1 the morphology key is `surah + ayah + word_position`.
/// Per §13, `grammar_tags` must only be populated when the selected source
/// genuinely provides grammatical (i'rab) analysis — never derived from
/// `part_of_speech` as a substitute.
const String createMorphologyTable = '''
CREATE TABLE morphology (
  surah_id INTEGER NOT NULL,
  ayah_number INTEGER NOT NULL,
  word_position INTEGER NOT NULL,
  word_key TEXT NOT NULL,
  root TEXT,
  lemma TEXT,
  stem TEXT,
  part_of_speech TEXT,
  grammar_tags TEXT,
  PRIMARY KEY (surah_id, ayah_number, word_position),
  FOREIGN KEY (surah_id, ayah_number, word_position)
    REFERENCES words (surah_id, ayah_number, word_position)
);
''';

/// `audio_assets` — Reciter/file metadata. Key: `audio_id`.
/// Either `ayah_key` (ayah-level file) or `surah_id` (surah-level file)
/// is populated depending on the recitation resource's granularity (§14).
/// `file_path` holds a remote `https://` URL, not an on-device path — the
/// ingested recitation resource (Prompt 13) is itself only metadata (a URL
/// + timing per ayah), and bundling actual recitation audio in the app the
/// way the 604 QPC V2 fonts were bundled isn't practical (many hundreds of
/// MB to low GB); playback streams this URL at runtime instead. `duration
/// _ms` is derived from the last segment's own `end_ms` at ingestion time
/// (the source's own duration field is empty) — an approximation only,
/// good enough for display before the real audio loads.
const String createAudioAssetsTable = '''
CREATE TABLE audio_assets (
  audio_id TEXT PRIMARY KEY,
  reciter_id TEXT NOT NULL,
  reciter_name TEXT,
  surah_id INTEGER,
  ayah_key TEXT,
  file_path TEXT NOT NULL,
  format TEXT,
  duration_ms INTEGER,
  FOREIGN KEY (surah_id) REFERENCES surahs (surah_id)
);
''';

/// `audio_segments` — Timing metadata. Key: `(audio_id, segment_index)`.
/// Used for synchronized word/ayah highlighting (§14).
/// `segment_index` is the segment's own 0-based position within the
/// recitation's timing array for that ayah — not `word_key`'s word
/// position, because a reciter can audibly repeat a phrase mid-ayah (found
/// in ~1% of ayahs in the ingested resource, e.g. 2:68), which puts the
/// same word position at two different points in the array with two
/// different timestamps. `word_key` is `null` when a segment doesn't
/// resolve to a real word (e.g. it lands on the ayah-end marker, or on a
/// rare extra trailing segment some sources include) rather than the
/// segment being an ingestion gap — see
/// tool/resource_manifest_seed.dart's `audioModuleResourceManifestSeed`.
const String createAudioSegmentsTable = '''
CREATE TABLE audio_segments (
  audio_id TEXT NOT NULL,
  segment_index INTEGER NOT NULL,
  word_key TEXT,
  ayah_key TEXT,
  start_ms INTEGER NOT NULL,
  end_ms INTEGER NOT NULL,
  PRIMARY KEY (audio_id, segment_index),
  FOREIGN KEY (audio_id) REFERENCES audio_assets (audio_id)
);
''';

/// `resource_manifest` — Version/license/source tracking. Key: `resource_id`.
/// Mandatory for every imported dataset (§16, §27) — no exceptions.
/// `attribution_text` is not in the §16 column list verbatim but is
/// required by §27 ("Record attribution text required by the
/// provider/resource") — added here since this table has no data yet and
/// this is the cheapest point to include it.
const String createResourceManifestTable = '''
CREATE TABLE resource_manifest (
  resource_id TEXT PRIMARY KEY,
  resource_name TEXT NOT NULL,
  provider TEXT,
  category TEXT,
  source_url TEXT,
  download_format TEXT,
  version_or_revision TEXT,
  retrieved_at TEXT,
  license_or_terms_url TEXT,
  sha256 TEXT,
  target_table_or_asset_path TEXT,
  compatibility_group TEXT,
  status TEXT,
  attribution_text TEXT
);
''';

/// `bookmarks` — User bookmarks. Key: `(user_id, ayah_key)`.
/// Bookmarks must attach to ayah identity, not page pixels (§19).
const String createBookmarksTable = '''
CREATE TABLE bookmarks (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id TEXT NOT NULL,
  ayah_key TEXT NOT NULL,
  created_at TEXT NOT NULL,
  UNIQUE (user_id, ayah_key)
);
''';

/// `notes` — User notes. Key: `note_id`.
/// Notes must attach to ayah identity, not page pixels (§19).
const String createNotesTable = '''
CREATE TABLE notes (
  note_id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  ayah_key TEXT NOT NULL,
  content TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT
);
''';

/// `reading_state` — Last read position. Key: `user_id`.
/// Restoring last-read must not fall back to page 1 (§19).
const String createReadingStateTable = '''
CREATE TABLE reading_state (
  user_id TEXT PRIMARY KEY,
  page_number INTEGER,
  surah_id INTEGER,
  ayah_number INTEGER,
  ayah_key TEXT,
  updated_at TEXT NOT NULL
);
''';

/// All CREATE TABLE statements, in dependency order (referenced tables
/// before referencing tables) so they can be executed sequentially against
/// a fresh database.
const List<String> createTableStatements = [
  createSurahsTable,
  createAyahsTable,
  createWordsTable,
  createMushafLinesTable,
  createTafsirSourcesTable,
  createTafsirEntriesTable,
  createMorphologyTable,
  createAudioAssetsTable,
  createAudioSegmentsTable,
  createResourceManifestTable,
  createBookmarksTable,
  createNotesTable,
  createReadingStateTable,
];

/// Required indexes — exact set specified in spec §15.1, verbatim.
const List<String> createIndexStatements = [
  'CREATE INDEX idx_ayah ON ayahs(surah_id, ayah_number);',
  'CREATE INDEX idx_words ON words(surah_id, ayah_number, word_position);',
  'CREATE INDEX idx_mushaf_lines ON mushaf_lines(page_number, line_number);',
  'CREATE INDEX idx_tafsir ON tafsir_entries(source_id, ayah_key);',
  'CREATE INDEX idx_morphology ON morphology(surah_id, ayah_number, word_position);',
];

/// Supplementary indexes beyond spec §15.1's literal list — not required
/// there verbatim, added for query paths that list itself doesn't cover.
/// `idx_tafsir_group` speeds up [TafsirRepository.getGroup]'s "find every
/// member ayah of this group" query (`WHERE source_id = ? AND group_id =
/// ?`), which `idx_tafsir` (keyed on `ayah_key`, not `group_id`) can't
/// serve.
const List<String> additionalIndexStatements = [
  'CREATE INDEX idx_tafsir_group ON tafsir_entries(source_id, group_id);',
];
