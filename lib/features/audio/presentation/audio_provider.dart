import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../domain/audio_repository.dart';
import '../domain/audio_segment.dart';
import '../domain/audio_track.dart';

/// App-wide audio playback state (spec §17.1's `AudioProvider`:
/// `reciter`, `isPlaying`, `position`, `currentAyah`, `currentWord`,
/// `segments`). Wraps a single `just_audio` `AudioPlayer` that streams
/// [AudioTrack.filePath] directly (a remote URL — see that class's doc
/// comment) rather than downloading/bundling audio files.
///
/// On every playback-position update, resolves which [AudioSegment] is
/// currently playing and republishes its `word_key` as [currentWordKey] —
/// spec §14's AudioController: "On playback progress: -> resolve current
/// segment -> map to word/ayah -> update highlight state." A segment with
/// no `word_key` (the ayah-end marker, or a rare extra segment — see
/// [AudioSegment]'s doc comment) simply clears the highlight instead of
/// pointing at a nonexistent word.
class AudioProvider extends ChangeNotifier {
  AudioProvider({required AudioRepository audioRepository, this.reciterId})
      : _audioRepository = audioRepository {
    _positionSubscription = _player.positionStream.listen(_onPositionChanged);
    _playerStateSubscription = _player.playerStateStream.listen(
      _onPlayerStateChanged,
    );
  }

  final AudioRepository _audioRepository;
  final AudioPlayer _player = AudioPlayer();
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<PlayerState>? _playerStateSubscription;

  /// Fixed to the single ingested reciter for now (Prompt 13 — only one
  /// reciter was downloaded, spec §14 doesn't require a picker yet).
  String? reciterId;

  String? _currentAyahKey;
  AudioTrack? _track;
  List<AudioSegment> _segments = const [];
  bool _isLoading = false;
  Object? _error;
  Duration _position = Duration.zero;
  bool _isPlaying = false;

  String? get currentAyahKey => _currentAyahKey;
  AudioTrack? get track => _track;
  List<AudioSegment> get segments => _segments;
  bool get isLoading => _isLoading;
  Object? get error => _error;
  Duration get position => _position;
  Duration get duration =>
      _player.duration ??
      Duration(milliseconds: _track?.durationMs ?? 0);
  bool get isPlaying => _isPlaying;

  /// The `word_key` of whichever segment [position] currently falls
  /// within, or `null` when playback is stopped/between highlightable
  /// segments — what [QuranAyahText] compares each word against to
  /// decide whether to highlight it.
  String? get currentWordKey {
    if (!_isPlaying && _position == Duration.zero) return null;
    final int positionMs = _position.inMilliseconds;
    for (final segment in _segments) {
      if (segment.contains(positionMs)) return segment.wordKey;
    }
    return null;
  }

  /// Loads (if needed) and plays [ayahKey]'s recording. Tapping play again
  /// on the *same* ayah that's already loaded just resumes/toggles instead
  /// of re-fetching — see [togglePlayPauseOrLoad].
  Future<void> playAyah(String ayahKey) async {
    final String? reciter = reciterId;
    if (reciter == null) return;

    if (_currentAyahKey == ayahKey && _track != null && _error == null) {
      await _player.seek(Duration.zero);
      await _player.play();
      return;
    }

    _isLoading = true;
    _error = null;
    _currentAyahKey = ayahKey;
    _track = null;
    _segments = const [];
    _position = Duration.zero;
    notifyListeners();

    try {
      final track = await _audioRepository.getAyahAudio(reciter, ayahKey);
      final segments = await _audioRepository.getSegments(reciter, ayahKey);
      if (track == null) {
        throw StateError('No audio track for reciter "$reciter", $ayahKey.');
      }
      _track = track;
      _segments = segments;
      await _player.setUrl(track.filePath);
      await _player.play();
    } catch (e) {
      _error = e;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Plays [ayahKey] if nothing is loaded for it yet, otherwise toggles
  /// play/pause on the already-loaded track — what the Ayah Context
  /// Sheet's single play/pause button calls, since it doesn't track
  /// loading state itself.
  Future<void> togglePlayPauseOrLoad(String ayahKey) async {
    if (_currentAyahKey != ayahKey || _track == null) {
      await playAyah(ayahKey);
      return;
    }
    if (_isPlaying) {
      await _player.pause();
    } else {
      await _player.play();
    }
  }

  Future<void> pause() => _player.pause();

  void _onPositionChanged(Duration position) {
    _position = position;
    notifyListeners();
  }

  void _onPlayerStateChanged(PlayerState state) {
    _isPlaying = state.playing;
    notifyListeners();
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _playerStateSubscription?.cancel();
    _player.dispose();
    super.dispose();
  }
}
