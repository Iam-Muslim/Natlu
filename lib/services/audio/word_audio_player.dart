import 'dart:async';
import 'dart:developer' show log;
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import '../../state/app_state.dart';
import '../quran_audio_service.dart';

/// Word audio playback service directly matching the stability, error handling,
/// and streaming architecture of `quran_library/lib/src/quran/core/services/word_audio_service.dart`.
///
/// Features from reference:
/// - Plays isolated Word-by-Word (WBW) audio files from `https://audio.qurancdn.com/wbw/{sss}_{aaa}_{www}.mp3`.
/// - Supports both single-word playback and sequential ayah-words playback via [AudioSource.uri] and [setAudioSources].
/// - Tracks active word in sequence via [currentIndexStream].
/// - Central subscription cleanup via [cancelAllSubscriptions] to prevent memory leaks and zombie streams.
/// - Catches [PlatformException] and network drops gracefully.
class WordAudioPlayer {
  static const String _cdnBase = 'https://audio.qurancdn.com';

  AudioPlayer? _player;
  StreamSubscription<PlayerState>? _playerStateSub;
  StreamSubscription<int?>? _currentIndexSub;

  int _sessionId = 0;
  bool _isPaused = false;
  int? _activeSurah;
  int? _activeAyah;
  int? _activeWordIndex;
  bool _isPlayingAyahWords = false;

  bool get isPaused => _isPaused;
  bool get isPlaying => _player?.playing ?? false;
  int? get activeSurah => _activeSurah;
  int? get activeAyah => _activeAyah;
  int? get activeWordIndex => _activeWordIndex;
  bool get isPlayingAyahWords => _isPlayingAyahWords;

  AudioPlayer get _audioPlayer {
    _player ??= AudioPlayer();
    return _player!;
  }

  /// Builds the Word-by-Word (WBW) direct URL matching the reference app:
  /// `https://audio.qurancdn.com/wbw/{sss}_{aaa}_{www}.mp3`
  static String buildWordUrl({
    required int surahNumber,
    required int ayahNumber,
    required int wordNumber1Based,
  }) {
    final s = surahNumber.toString().padLeft(3, '0');
    final a = ayahNumber.toString().padLeft(3, '0');
    final w = wordNumber1Based.toString().padLeft(3, '0');
    return '$_cdnBase/wbw/${s}_${a}_$w.mp3';
  }

  /// Cancels all active subscriptions (matching reference `cancelAllSubscriptions`).
  void cancelAllSubscriptions() {
    _playerStateSub?.cancel();
    _playerStateSub = null;
    _currentIndexSub?.cancel();
    _currentIndexSub = null;
  }

  /// Plays a single word's direct audio slice using Sheikh Al-Husary from MP3Quran.
  Future<void> playWord({
    required int surah,
    required int ayah,
    required int wordIndex,
  }) async {
    await QuranAudioService.instance.playWord(
      surah: surah,
      ayah: ayah,
      wordIndex: wordIndex,
    );
  }

  /// Plays all words of an Ayah sequentially via an audio playlist
  /// (directly matching `WordAudioService.playAyahWords` from reference).
  Future<void> playAyahWords({
    required int surah,
    required int ayah,
    required int totalWords,
  }) async {
    final int session = ++_sessionId;
    if (totalWords <= 0) return;

    _isPaused = false;
    _activeSurah = surah;
    _activeAyah = ayah;
    _activeWordIndex = 0;
    _isPlayingAyahWords = true;

    final app = AppState.instance;
    app.activeAudioSurah.value = surah;
    app.activeAudioAyah.value = ayah;
    app.activeAudioWordIndex.value = 0;
    app.isContinuousPlayback.value = false;
    app.isAudioBuffering.value = true;
    app.isAudioPlaying.value = false;

    try {
      cancelAllSubscriptions();
      try {
        await _player?.stop();
      } catch (_) {}
      if (session != _sessionId) return;

      final sources = List<AudioSource>.generate(
        totalWords,
        (i) => AudioSource.uri(
          Uri.parse(buildWordUrl(
            surahNumber: surah,
            ayahNumber: ayah,
            wordNumber1Based: i + 1,
          )),
        ),
      );

      final p = _audioPlayer;
      await p.setAudioSources(sources);
      if (session != _sessionId) return;

      // Track active word index across playlist transitions
      _currentIndexSub = p.currentIndexStream.listen((index) {
        if (session != _sessionId) return;
        if (index != null && index < totalWords) {
          _activeWordIndex = index;
          if (AppState.instance.activeAudioWordIndex.value != index) {
            AppState.instance.activeAudioWordIndex.value = index;
          }
        }
      });

      _listenForCompletion(session);

      app.isAudioBuffering.value = false;
      app.isAudioPlaying.value = true;

      await p.play();
    } catch (e, stack) {
      if (session == _sessionId) {
        log('Error in WordAudioPlayer.playAyahWords: $e',
            name: 'WordAudioPlayer', error: e, stackTrace: stack);
        _resetState();
        AppState.instance.triggerAudioError(AudioFailureReason.networkOffline);
      }
    }
  }

  /// Pauses the active word recitation.
  Future<void> pause() async {
    _isPaused = true;
    try {
      await _player?.pause();
    } catch (_) {}
    final app = AppState.instance;
    app.isAudioPlaying.value = false;
    app.isAudioBuffering.value = false;
  }

  /// Resumes the paused word recitation.
  Future<void> resume() async {
    _isPaused = false;
    final app = AppState.instance;
    app.isAudioBuffering.value = false;
    app.isAudioPlaying.value = true;
    try {
      await _player?.play();
    } catch (_) {}
  }

  /// Completely stops playback and resets word highlight.
  Future<void> stop() async {
    _sessionId++;
    cancelAllSubscriptions();
    _isPaused = false;
    try {
      if (_player != null) {
        await _player!.stop();
      }
    } catch (_) {}
    _resetState();
  }

  bool _isHandlingComplete = false;
  double _lastCompleteTime = 0.0;

  void _listenForCompletion(int session) {
    _playerStateSub?.cancel();
    _playerStateSub = _audioPlayer.playerStateStream.listen((state) {
      if (session != _sessionId) return;

      final isBuffering = state.processingState == ProcessingState.buffering ||
          state.processingState == ProcessingState.loading;
      AppState.instance.isAudioBuffering.value = isBuffering;

      if (state.processingState == ProcessingState.completed) {
        final now = DateTime.now().millisecondsSinceEpoch / 1000.0;
        if (_isHandlingComplete || (now - _lastCompleteTime) < 1.0) return;
        _isHandlingComplete = true;
        _lastCompleteTime = now;
        try {
          _resetState();
          cancelAllSubscriptions();
        } finally {
          _isHandlingComplete = false;
        }
      }
    });
  }

  void _resetState() {
    _isPaused = false;
    _activeSurah = null;
    _activeAyah = null;
    _activeWordIndex = null;
    _isPlayingAyahWords = false;

    final app = AppState.instance;
    app.isAudioPlaying.value = false;
    app.isAudioBuffering.value = false;
    app.activeAudioWordIndex.value = null;
    app.activeAudioAyah.value = null;
  }

  Future<void> dispose() async {
    await stop();
    cancelAllSubscriptions();
    try {
      await _player?.dispose();
    } catch (_) {}
    _player = null;
  }
}
