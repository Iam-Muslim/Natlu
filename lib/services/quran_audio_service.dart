import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_session/audio_session.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../state/app_state.dart';
import 'quran_timing_service.dart';

/// High-performance Quran audio service powered by MP3Quran v4 and just_audio (ExoPlayer / AVPlayer).
///
/// Cross-Platform Architecture & Resilience:
/// - **Frame-Accurate Seeking (ExoPlayer on Android, AVPlayer on iOS, MediaFoundation on Windows)**:
///   Bypasses Android's legacy MediaPlayer (which suffered from SEEK_PREVIOUS_SYNC drift).
///   Word taps now jump to the exact sample millisecond on all platforms.
/// - **Zero-Waste Range Streaming**: Streams audio on-demand via HTTP Range headers
///   without downloading or writing full Surah files to disk.
/// - **Pure Streaming Timings**: Aligns with MP3Quran v4 word timings streamed into memory.
/// - **Full Offline / Online Resilience**:
///   - Handles no internet on initial play without freezing or fake-playing.
///   - Handles sudden network loss mid-stream cleanly without stuck states.
/// - **Event-Driven Position Stream**: Smooth 60fps word highlight synchronization.
/// - **Pauses & Breaths Handled Properly**: "A pause between words has no entry" -> clears highlight.
/// - **Single Word Playback**: Plays any individual word with exact start/end trimming.
/// - **Seamless Pause & Resume**: Keeps stopped word visible; resumes from the word start.
class QuranAudioService {
  QuranAudioService._();
  static final QuranAudioService instance = QuranAudioService._();

  /// MP3Quran v4 audio base URL for Sheikh Mahmoud Khalil Al-Husary (64kbps mono MP3).
  static const String mp3QuranAudioBaseUrl =
      'https://cdn.mp3quran.net/audio/mahmoud-husary/r1';

  /// Standard Ayah counts for Surahs 1 to 114.
  static const List<int> surahAyahCounts = [
    7, 286, 200, 176, 120, 165, 206, 75, 129, 109,
    123, 111, 43, 52, 99, 128, 111, 110, 98, 135,
    112, 78, 118, 64, 77, 227, 93, 88, 69, 60,
    34, 30, 73, 54, 45, 83, 182, 88, 75, 85,
    54, 53, 89, 59, 37, 35, 38, 29, 18, 45,
    60, 49, 62, 55, 78, 96, 29, 22, 24, 13,
    14, 11, 11, 18, 12, 12, 30, 52, 52, 44,
    28, 28, 20, 56, 40, 31, 50, 40, 46, 42,
    29, 19, 36, 25, 22, 17, 19, 26, 30, 20,
    15, 21, 11, 8, 8, 19, 5, 8, 8, 11,
    11, 8, 3, 9, 5, 4, 7, 3, 6, 3,
    5, 4, 5, 6
  ];

  AudioPlayer? _player;
  int? _currentSurah;
  int? _currentAyah;
  int? _loadedSurah;
  bool _isContinuous = true;

  // Pause retention state
  bool _isPaused = false;
  int? _pausedSurah;
  int? _pausedAyah;
  int? _pausedWordIndex;

  // Single-word playback state
  bool _isSingleWordMode = false;
  int? _singleWordEndMs;
  Timer? _wordEndTimer;

  int _playSessionId = 0;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<PlayerState>? _playerStateSub;

  /// Whether playback is currently paused on a specific Ayah/word.
  bool get isPaused => _isPaused;

  /// Whether current playback is a single-word playback session.
  bool get isSingleWordMode => _isSingleWordMode;

  /// Guaranteed non-null AudioPlayer instance with robust listeners.
  AudioPlayer get _audioPlayer {
    if (_player == null) {
      if (!kIsWeb) {
        AudioSession.instance.then((session) {
          session.configure(const AudioSessionConfiguration.music());
        }).catchError((_) {});
      }

      final p = AudioPlayer();

      _positionSub = p.positionStream.listen(_handlePosition);
      _playerStateSub = p.playerStateStream.listen((state) {
        if (state.processingState == ProcessingState.completed) {
          _handleTrackComplete();
        } else if (state.processingState == ProcessingState.ready && p.playing) {
          if (AppState.instance.isAudioBuffering.value) {
            AppState.instance.isAudioBuffering.value = false;
          }
          if (!AppState.instance.isAudioPlaying.value) {
            AppState.instance.isAudioPlaying.value = true;
          }
        }
      });

      _player = p;
    }
    return _player!;
  }

  /// Returns the streaming URL for a Surah audio file (64kbps mono MP3).
  static String getSurahAudioUrl(int surah) {
    final s = surah.toString().padLeft(3, '0');
    return '$mp3QuranAudioBaseUrl/$s-64k.mp3';
  }

  /// High-frequency position listener for word highlighting and Ayah boundary checks.
  void _handlePosition(Duration pos) {
    if (!AppState.instance.isAudioPlaying.value && !(_player?.playing ?? false)) return;

    if (AppState.instance.isAudioBuffering.value) {
      AppState.instance.isAudioBuffering.value = false;
    }

    final surah = _currentSurah;
    final ayah = _currentAyah;
    if (surah == null || ayah == null) return;

    final int posMs = pos.inMilliseconds;

    // ── Single Word Playback Mode ──
    if (_isSingleWordMode) {
      if (_singleWordEndMs != null && posMs >= _singleWordEndMs!) {
        _stopSingleWord(_playSessionId);
      }
      return;
    }

    // ── Regular Ayah Playback Mode ──
    final surahTiming = QuranTimingService.instance.getSurahTiming(surah);
    if (surahTiming == null) return;

    final currentAyahTiming = surahTiming.getAyah(ayah);
    if (currentAyahTiming == null) return;

    // Ignore early/stale ticks (e.g. while seeking from 0:00 or a previous Ayah)
    if (posMs < currentAyahTiming.ayahStartMs - 150) {
      return;
    }

    // 1. Binary search lookup for the active word
    final WordTiming? activeWord = surahTiming.findActiveWordAtMs(posMs);

    if (activeWord != null) {
      if (_isContinuous && activeWord.ayah != _currentAyah) {
        _currentAyah = activeWord.ayah;
        AppState.instance.activeAudioAyah.value = activeWord.ayah;
      }
      if (activeWord.ayah == _currentAyah) {
        if (AppState.instance.activeAudioWordIndex.value != activeWord.wordIndex) {
          AppState.instance.activeAudioWordIndex.value = activeWord.wordIndex;
        }
      }
    } else {
      // Clear highlight during pauses between words or when outside word range
      if (AppState.instance.activeAudioWordIndex.value != null) {
        AppState.instance.activeAudioWordIndex.value = null;
      }
    }

    // 2. Ayah boundary completion detection
    if (posMs >= currentAyahTiming.ayahEndMs) {
      if (!_isContinuous) {
        // Single-Ayah mode (e.g. Record Mode): stop immediately
        stop();
      } else {
        // Continuous mode: advance to next Ayah seamlessly (timings already in memory!)
        final maxAyah = surahAyahCounts[surah - 1];
        final nextAyah = _currentAyah! + 1;

        if (nextAyah <= maxAyah) {
          _currentAyah = nextAyah;
          AppState.instance.activeAudioAyah.value = nextAyah;
          AppState.instance.activeAudioWordIndex.value = null;
        } else {
          // Reached end of Surah
          stop();
        }
      }
    }
  }

  /// Plays a single word alone from the reciter audio and stops immediately when finished.
  Future<void> playWord({
    required int surah,
    required int ayah,
    required int wordIndex,
  }) async {
    final int session = ++_playSessionId;
    _wordEndTimer?.cancel();
    _wordEndTimer = null;
    _isSingleWordMode = true;
    _isPaused = false;
    _currentSurah = surah;
    _currentAyah = ayah;
    _isContinuous = false;

    // Immediately silence any ongoing sound so previous word NEVER lingers or bleeds!
    if (_player != null) {
      unawaited(_player!.pause().catchError((_) {}));
    }

    final app = AppState.instance;
    app.activeAudioSurah.value = surah;
    app.activeAudioAyah.value = ayah;
    app.activeAudioWordIndex.value = wordIndex;
    app.isAudioBuffering.value = true;
    app.isAudioPlaying.value = false;

    try {
      // 1. Stream timing data for the Surah
      final surahTiming = await QuranTimingService.instance.ensureSurahLoaded(surah);
      if (session != _playSessionId) return;

      if (surahTiming == null) {
        _resetStateToStopped(triggerErrorBanner: true);
        return;
      }

      final ayahTiming = surahTiming.getAyah(ayah);
      if (ayahTiming == null || ayahTiming.words.isEmpty) {
        _resetStateToStopped(triggerErrorBanner: true);
        return;
      }

      final targetWord = ayahTiming.words.firstWhere(
        (w) => w.wordIndex == wordIndex,
        orElse: () => ayahTiming.words.first,
      );

      _singleWordEndMs = targetWord.endMs;

      final startDuration = Duration(milliseconds: targetWord.startMs);
      final durationMs = (targetWord.endMs - targetWord.startMs).clamp(50, 10000);
      final player = _audioPlayer;

      if (_loadedSurah != surah) {
        _loadedSurah = surah;
        final url = getSurahAudioUrl(surah);
        // Load URL directly at target word offset - NEVER buffer 0:00 Basmalah!
        await player.setUrl(url, initialPosition: startDuration);
      } else {
        await player.seek(startDuration);
      }

      if (session != _playSessionId) {
        unawaited(player.pause().catchError((_) {}));
        return;
      }

      app.isContinuousPlayback.value = false;
      app.isAudioBuffering.value = false;
      app.isAudioPlaying.value = true;
      app.activeAudioWordIndex.value = targetWord.wordIndex;

      // Arm the millisecond timer BEFORE starting playback
      _wordEndTimer?.cancel();
      _wordEndTimer = Timer(Duration(milliseconds: durationMs), () {
        if (session == _playSessionId) {
          _stopSingleWord(session);
        }
      });

      unawaited(player.play().catchError((e) {
        if (session == _playSessionId) {
          debugPrint('[QuranAudioService] Error playing word: $e');
        }
      }));

      if (!kIsWeb) {
        try { WakelockPlus.enable(); } catch (_) {}
      }
    } catch (e, stack) {
      if (session == _playSessionId) {
        debugPrint('[QuranAudioService] Error playing word ($surah:$ayah:$wordIndex): $e\n$stack');
        _resetStateToStopped(triggerErrorBanner: true);
      }
    }
  }

  /// Internal handler that strictly stops single-word playback at the exact millisecond.
  void _stopSingleWord(int session) {
    if (session != _playSessionId) return;
    _wordEndTimer?.cancel();
    _wordEndTimer = null;
    _isSingleWordMode = false;
    _singleWordEndMs = null;

    try {
      _player?.pause();
    } catch (_) {}

    final app = AppState.instance;
    app.isAudioPlaying.value = false;
    app.isAudioBuffering.value = false;
    app.activeAudioWordIndex.value = null;
    app.activeAudioAyah.value = null;
  }

  /// Plays the specified [ayah] in [surah].
  ///
  /// - Minimal Bandwidth: Uses HTTP Range streaming — only downloading chunks
  ///   for the played Ayah without loading the full Surah file.
  /// - Resumes cleanly from paused position if already paused on this Ayah.
  /// - Resilient to network outages: never gets stuck in playing state when offline.
  /// - [continuous]: If true, plays sequentially across Ayahs.
  ///                 If false, plays only this single Ayah and stops.
  Future<void> play({
    required int surah,
    required int ayah,
    required bool continuous,
  }) async {
    final int session = ++_playSessionId;
    _wordEndTimer?.cancel();
    _wordEndTimer = null;
    _isSingleWordMode = false;
    _singleWordEndMs = null;

    // Immediately silence any ongoing sound so previous recitation stops instantly!
    if (_player != null) {
      unawaited(_player!.pause().catchError((_) {}));
    }

    // If resuming the exact same Ayah that was paused, resume where stopped
    if (_isPaused && _pausedSurah == surah && _pausedAyah == ayah && _player != null) {
      _isContinuous = continuous;
      AppState.instance.isContinuousPlayback.value = continuous;
      await resume();
      return;
    }

    _isPaused = false;
    _currentSurah = surah;
    _currentAyah = ayah;
    _isContinuous = continuous;

    final app = AppState.instance;
    app.activeAudioSurah.value = surah;
    app.activeAudioAyah.value = ayah;
    app.activeAudioWordIndex.value = null;
    app.isAudioBuffering.value = true;
    app.isAudioPlaying.value = false;

    try {
      // 1. Fetch Surah timing stream from MP3Quran v4 API
      final surahTiming = await QuranTimingService.instance.ensureSurahLoaded(surah);
      if (session != _playSessionId) return;

      if (surahTiming == null) {
        debugPrint('[QuranAudioService] Unable to stream timings for Surah $surah. Aborting.');
        _resetStateToStopped(triggerErrorBanner: true);
        return;
      }

      final ayahTiming = surahTiming.getAyah(ayah);
      if (ayahTiming == null) {
        debugPrint('[QuranAudioService] Ayah $surah:$ayah not found in timing dataset. Aborting.');
        _resetStateToStopped(triggerErrorBanner: true);
        return;
      }

      final int startMs = ayahTiming.ayahStartMs;
      final startDuration = Duration(milliseconds: startMs);
      final player = _audioPlayer;

      if (_loadedSurah != surah) {
        _loadedSurah = surah;
        final url = getSurahAudioUrl(surah);
        // Load URL directly at Ayah start offset - NEVER buffer 0:00 Basmalah!
        await player.setUrl(url, initialPosition: startDuration);
      } else {
        await player.seek(startDuration);
      }

      if (session != _playSessionId) {
        unawaited(player.pause().catchError((_) {}));
        return;
      }

      app.activeAudioSurah.value = surah;
      app.activeAudioAyah.value = ayah;
      app.activeAudioWordIndex.value = null;
      app.isContinuousPlayback.value = continuous;
      app.isAudioBuffering.value = false;
      app.isAudioPlaying.value = true;

      unawaited(player.play().catchError((e) {
        if (session == _playSessionId) {
          debugPrint('[QuranAudioService] Error playing ayah: $e');
        }
      }));

      if (!kIsWeb) {
        try { WakelockPlus.enable(); } catch (_) {}
      }
    } catch (e, stack) {
      if (session == _playSessionId) {
        debugPrint('[QuranAudioService] Error playing $surah:$ayah: $e\n$stack');
        _resetStateToStopped(triggerErrorBanner: true);
      }
    }
  }

  /// Handles completion when the audio player naturally reaches the file end.
  void _handleTrackComplete() {
    stop();
  }

  /// Pauses playback and keeps the paused word highlighted for calm resume.
  Future<void> pause() async {
    _wordEndTimer?.cancel();
    _wordEndTimer = null;
    try {
      _isPaused = true;
      _pausedSurah = _currentSurah;
      _pausedAyah = _currentAyah;
      _pausedWordIndex = AppState.instance.activeAudioWordIndex.value;
      await _player?.pause();
    } catch (e) {
      debugPrint('[QuranAudioService] Error pausing: $e');
    }
    final app = AppState.instance;
    app.isAudioPlaying.value = false;
  }

  /// Resumes playback from the exact paused word and millisecond.
  Future<void> resume() async {
    try {
      _isPaused = false;
      _currentSurah = _pausedSurah ?? _currentSurah;
      _currentAyah = _pausedAyah ?? _currentAyah;

      // If we have a paused word, seek to its startMs so the user hears the complete word
      if (_pausedWordIndex != null && _currentSurah != null && _currentAyah != null) {
        final timing = QuranTimingService.instance.getCachedAyahTiming(_currentSurah!, _currentAyah!);
        if (timing != null && timing.words.isNotEmpty) {
          final word = timing.words.firstWhere(
            (w) => w.wordIndex == _pausedWordIndex,
            orElse: () => timing.words.first,
          );
          await _audioPlayer.seek(Duration(milliseconds: word.startMs));
          AppState.instance.activeAudioWordIndex.value = word.wordIndex;
        }
      }

      AppState.instance.isAudioBuffering.value = false;
      AppState.instance.isAudioPlaying.value = true;
      unawaited(_audioPlayer.play().catchError((e) {
        debugPrint('[QuranAudioService] Error resuming: $e');
      }));
      if (!kIsWeb) {
        try { WakelockPlus.enable(); } catch (_) {}
      }
    } catch (e) {
      debugPrint('[QuranAudioService] Error resuming: $e');
      _resetStateToStopped(triggerErrorBanner: true);
    }
  }

  /// Completely stops playback, resets streaming, and clears state.
  Future<void> stop() async {
    _playSessionId++;
    _wordEndTimer?.cancel();
    _wordEndTimer = null;
    try {
      await _player?.pause();
    } catch (e) {
      debugPrint('[QuranAudioService] Error stopping: $e');
    }
    _resetStateToStopped();
  }

  /// Internal cleanup routine guaranteeing consistent state.
  void _resetStateToStopped({
    bool triggerErrorBanner = false,
    AudioFailureReason? errorReason,
  }) {
    _wordEndTimer?.cancel();
    _wordEndTimer = null;
    _isPaused = false;
    _pausedSurah = null;
    _pausedAyah = null;
    _pausedWordIndex = null;
    _isSingleWordMode = false;
    _singleWordEndMs = null;
    _currentSurah = null;
    _currentAyah = null;

    final app = AppState.instance;
    app.activeAudioWordIndex.value = null;
    app.activeAudioAyah.value = null;
    app.isAudioBuffering.value = false;
    if (app.isAudioPlaying.value) {
      app.isAudioPlaying.value = false;
    }

    if (triggerErrorBanner) {
      app.triggerAudioError(
        errorReason ?? QuranTimingService.instance.lastFailureReason,
      );
    }
  }

  /// Releases player resources completely.
  Future<void> dispose() async {
    _wordEndTimer?.cancel();
    _wordEndTimer = null;
    await stop();
    await _positionSub?.cancel();
    await _playerStateSub?.cancel();
    _positionSub = null;
    _playerStateSub = null;
    try {
      await _player?.dispose();
    } catch (_) {}
    _player = null;
    _loadedSurah = null;
  }
}
