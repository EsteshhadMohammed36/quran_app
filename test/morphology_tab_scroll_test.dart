import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:quran_app/features/audio/domain/audio_repository.dart';
import 'package:quran_app/features/audio/domain/audio_segment.dart';
import 'package:quran_app/features/audio/domain/audio_track.dart';
import 'package:quran_app/features/audio/domain/reciter.dart';
import 'package:quran_app/features/audio/presentation/audio_provider.dart';
import 'package:quran_app/features/ayah_study/presentation/ayah_context_sheet.dart';
import 'package:quran_app/features/bookmarks/domain/bookmark.dart';
import 'package:quran_app/features/bookmarks/domain/bookmark_repository.dart';
import 'package:quran_app/features/last_read/domain/reading_state.dart';
import 'package:quran_app/features/last_read/domain/reading_state_repository.dart';
import 'package:quran_app/features/morphology/domain/morphology_entry.dart';
import 'package:quran_app/features/morphology/domain/morphology_repository.dart';
import 'package:quran_app/features/morphology/presentation/morphology_tab_content.dart';
import 'package:quran_app/features/notes/domain/note.dart';
import 'package:quran_app/features/notes/domain/note_repository.dart';
import 'package:quran_app/features/quran_reader/domain/ayah.dart';
import 'package:quran_app/features/quran_reader/domain/mushaf_page.dart';
import 'package:quran_app/features/quran_reader/domain/quran_repository.dart';
import 'package:quran_app/features/quran_reader/domain/surah.dart';
import 'package:quran_app/features/quran_reader/domain/word.dart';
import 'package:quran_app/features/quran_reader/presentation/quran_reader_provider.dart';
import 'package:quran_app/features/tafsir/domain/tafsir_entry.dart';
import 'package:quran_app/features/tafsir/domain/tafsir_group.dart';
import 'package:quran_app/features/tafsir/domain/tafsir_repository.dart';
import 'package:quran_app/features/tafsir/domain/tafsir_source.dart';
import 'package:quran_app/features/user_library/presentation/user_library_provider.dart';

/// Regression test for the Morphology tab's horizontal word-card strip
/// (spec §12.2). Verifies via [WidgetTester.drag] — a real Flutter
/// scroll gesture, not `adb input swipe` (which this session found doesn't
/// reliably drive drag gestures on the emulator used for manual
/// verification) — that every word's card is actually reachable by
/// scrolling, not just the first few that fit on screen.
class _FakeQuranRepository implements QuranRepository {
  _FakeQuranRepository(this.words);

  final List<Word> words;

  @override
  Future<Surah> getSurah(int surahId) async => const Surah(
        surahId: 1,
        nameArabic: 'الفاتحة',
        nameEnglish: null,
        nameTransliteration: 'Al-Fatihah',
        revelationPlace: 'makkah',
        ayahCount: 7,
      );

  @override
  Future<List<Surah>> getAllSurahs() => throw UnimplementedError();

  @override
  Future<Map<int, int>> getFirstPageNumbersForSurahs() =>
      throw UnimplementedError();

  @override
  Future<Ayah> getAyah(String ayahKey) => throw UnimplementedError();

  @override
  Future<MushafPage> getPage(int pageNumber) => throw UnimplementedError();

  @override
  Future<List<Word>> getWords(String ayahKey) async => words;

  @override
  Future<List<Word>> getWordsForPage(int pageNumber) =>
      throw UnimplementedError();

  @override
  Future<int> getPageCount() async => 1;

  @override
  Future<Map<int, int>> getPageNumbersForWordIndexes(
    List<int> wordIndexes,
  ) async => {for (final i in wordIndexes) i: 1};
}

class _FakeMorphologyRepository implements MorphologyRepository {
  _FakeMorphologyRepository(this.entries);

  final List<MorphologyEntry> entries;

  @override
  Future<List<MorphologyEntry>> getEntriesForAyah(String ayahKey) async =>
      entries;
}

/// Never actually queried by this test (no ayah is ever played), but
/// [AyahContextSheet] needs an [AudioProvider] in its ambient tree — see
/// `mushaf_reader_screen.dart`'s own wiring, which this test mirrors.
class _FakeAudioRepository implements AudioRepository {
  @override
  Future<List<Reciter>> getReciters() async => [];

  @override
  Future<AudioTrack?> getAyahAudio(String reciterId, String ayahKey) async =>
      null;

  @override
  Future<List<AudioSegment>> getSegments(
    String reciterId,
    String ayahKey,
  ) async => [];
}

/// Never actually exercised by this test (no bookmark/note is ever
/// created), but [AyahContextSheet]'s `_ActionsRow` needs a
/// [UserLibraryProvider] in its ambient tree — see `mushaf_reader_screen
/// .dart`'s own wiring, which this test mirrors (same reasoning as
/// `_FakeAudioRepository` above).
class _FakeBookmarkRepository implements BookmarkRepository {
  @override
  Future<List<Bookmark>> getBookmarks() async => [];

  @override
  Future<bool> isBookmarked(String ayahKey) async => false;

  @override
  Future<void> addBookmark(String ayahKey) async {}

  @override
  Future<void> removeBookmark(String ayahKey) async {}
}

class _FakeNoteRepository implements NoteRepository {
  @override
  Future<List<Note>> getAllNotes() async => [];

  @override
  Future<Note?> getNoteForAyah(String ayahKey) async => null;

  @override
  Future<Note> upsertNote(String ayahKey, String content) => throw UnimplementedError();

  @override
  Future<void> deleteNote(String noteId) async {}
}

class _FakeReadingStateRepository implements ReadingStateRepository {
  @override
  Future<ReadingState?> getReadingState() async => null;

  @override
  Future<void> saveReadingState({
    required int pageNumber,
    int? surahId,
    int? ayahNumber,
    String? ayahKey,
  }) async {}
}

class _FakeTafsirRepository implements TafsirRepository {
  @override
  Future<List<TafsirSource>> getSources() => throw UnimplementedError();

  @override
  Future<TafsirEntry> getEntry(String sourceId, String ayahKey) =>
      throw UnimplementedError();

  @override
  Future<TafsirGroup> getGroup(String sourceId, String ayahKey) =>
      throw UnimplementedError();

  @override
  Future<List<TafsirEntry>> search(String sourceId, String query) =>
      throw UnimplementedError();
}

void main() {
  testWidgets(
    'Morphology tab: every word card is reachable by scrolling',
    (WidgetTester tester) async {
      final words = [
        for (var i = 1; i <= 5; i++)
          Word(
            surahId: 1,
            ayahNumber: 2,
            wordPosition: i,
            wordKey: '1:2:$i',
            wordIndex: 100 + i,
            text: 'WORD$i',
          ),
      ];
      final entries = [
        for (var i = 1; i <= 5; i++)
          MorphologyEntry(
            surahId: 1,
            ayahNumber: 2,
            wordPosition: i,
            wordKey: '1:2:$i',
            root: 'ROOT$i',
          ),
      ];

      // The default test surface (~800x600 logical) is far narrower/shorter
      // than a real phone and doesn't reflect the on-device layout this
      // widget was built for — use a realistic phone-sized viewport so the
      // scroll behavior under test matches what a real screen would show.
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final quranRepository = _FakeQuranRepository(words);
      final provider = QuranReaderProvider(
        repository: quranRepository,
        totalPages: 1,
      );
      provider.selectWord(
        const Word(
          surahId: 1,
          ayahNumber: 2,
          wordPosition: 1,
          wordKey: '1:2:1',
          wordIndex: 101,
          text: 'WORD1',
        ),
      );
      provider.setActiveStudyTab(StudyTab.morphology);

      final audioProvider = AudioProvider(
        audioRepository: _FakeAudioRepository(),
      );
      addTearDown(audioProvider.dispose);

      final userLibraryProvider = UserLibraryProvider(
        bookmarkRepository: _FakeBookmarkRepository(),
        noteRepository: _FakeNoteRepository(),
        readingStateRepository: _FakeReadingStateRepository(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: MultiProvider(
            providers: [
              ChangeNotifierProvider<QuranReaderProvider>.value(
                value: provider,
              ),
              ChangeNotifierProvider<AudioProvider>.value(
                value: audioProvider,
              ),
              ChangeNotifierProvider<UserLibraryProvider>.value(
                value: userLibraryProvider,
              ),
            ],
            child: Scaffold(
              body: const SizedBox.expand(),
              bottomSheet: AyahContextSheet(
                repository: quranRepository,
                tafsirRepository: _FakeTafsirRepository(),
                morphologyRepository: _FakeMorphologyRepository(entries),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Word 1 (first word, rightmost per RTL order) is on-screen initially;
      // word 5 (last word, leftmost) is scrolled off and not yet built.
      expect(find.text('ROOT1'), findsOneWidget);
      expect(find.text('ROOT5'), findsNothing);

      // Drag the horizontal card strip fully leftward (revealing higher
      // word positions, matching RTL reading order) and confirm the last
      // word's card becomes reachable.
      // A *positive* dx, not negative: for a `reverse: true` horizontal
      // list, the drag direction that advances through higher indices is
      // the mirror image of a normal (non-reversed) list's convention —
      // confirmed by instrumenting the underlying ScrollPosition directly
      // (a `-2000` drag left the horizontal Scrollable's offset at exactly
      // 0.0, i.e. it never moved at all; `+2000` drove it to its
      // maxScrollExtent). This was the test's own bug, not the widget's —
      // the widget's scroll direction is correct for RTL reading order
      // (word 1 does start at the right edge, as asserted above), it's
      // only *this line*'s sign that had reverse:true's mirroring backwards.
      await tester.drag(find.text('ROOT1'), const Offset(2000, 0));
      await tester.pumpAndSettle();

      expect(find.text('ROOT5'), findsOneWidget);
    },
  );

  testWidgets(
    'Morphology tab: the ayah-end marker word gets no card',
    (WidgetTester tester) async {
      // `words` mirrors what `QuranRepository.getWords` really returns for
      // any ayah: real words plus one trailing `word_type: 'end_marker'`
      // row (the circled-ayah-number ornament — see `Word
      // .isAyahEndMarker`'s doc comment and `schema.dart`'s `words` table
      // comment). The morphology repository never has an entry for it
      // (root/lemma/stem are meaningless for a non-word), matching real
      // ingested data.
      final words = [
        for (var i = 1; i <= 3; i++)
          Word(
            surahId: 1,
            ayahNumber: 4,
            wordPosition: i,
            wordKey: '1:4:$i',
            wordIndex: 100 + i,
            text: 'WORD$i',
          ),
        const Word(
          surahId: 1,
          ayahNumber: 4,
          wordPosition: 4,
          wordKey: '1:4:4',
          wordIndex: 104,
          text: 'MARKER',
          wordType: 'end_marker',
        ),
      ];
      final entries = [
        for (var i = 1; i <= 3; i++)
          MorphologyEntry(
            surahId: 1,
            ayahNumber: 4,
            wordPosition: i,
            wordKey: '1:4:$i',
            root: 'ROOT$i',
          ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MorphologyTabContent(
              ayahKey: '1:4',
              words: words,
              pageByWordIndex: {for (final w in words) w.wordIndex: 1},
              morphologyRepository: _FakeMorphologyRepository(entries),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The 3 real words get cards (their root shows up)...
      expect(find.text('ROOT1'), findsOneWidget);
      expect(find.text('ROOT2'), findsOneWidget);
      expect(find.text('ROOT3'), findsOneWidget);
      // ...but the marker gets no card at all — not even an empty one.
      expect(find.byType(MorphologyWordCard), findsNWidgets(3));
      expect(find.text('MARKER'), findsNothing);
    },
  );
}
