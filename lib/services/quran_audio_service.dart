import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_session/audio_session.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../state/app_state.dart';
import 'quran_timing_service.dart';

/// Professional, highly-stable Quran audio service for Sheikh Mahmoud Khalil Al-Husary.
///
/// Architectural Guarantees:
/// 1. **Exclusive Reciter**: Sheikh Mahmoud Khalil Al-Husary from MP3Quran
///    (`https://cdn.mp3quran.net/audio/mahmoud-husary/r1/{surah}-64k.mp3`) for BOTH full Ayahs and single-word taps.
/// 2. **Single-Word Tap Auditioning**: Seeks directly to the word's millisecond slice, highlights
///    that word alone, plays Husary's recitation, and stops immediately when the word completes.
/// 3. **Continuous Ayah Playback**: Out of Recording Mode (`continuous: true`), recites smoothly
///    across subsequent Ayahs with uninterrupted, synchronized word-by-word highlighting.
/// 4. **Recording Mode Isolation**: In Recording Mode (`continuous: false`), plays only the selected
///    Ayah and cleanly stops at its boundary.
/// 5. **Zero-Skip Synchronization**: Active Ayah and Word are governed by the single source of truth
///    (`SurahTiming.findActiveWordAtMs`). Eliminates double-increments, race conditions, and dropped highlights.
/// 6. **Stale Tick Lock (`_isSeeking`)**: Guards against platform-level buffer latency during seeks.
class QuranAudioService {
  QuranAudioService._();
  static final QuranAudioService instance = QuranAudioService._();

  /// MP3Quran base audio URL for Sheikh Mahmoud Khalil Al-Husary (64kbps mono MP3).
  static const String mp3QuranAudioBaseUrl =
      'https://cdn.mp3quran.net/audio/mahmoud-husary/r1';

  // ── 1. Player & Stream Subscriptions ───────────────────────────────────────
  AudioPlayer? _player;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<PlayerState>? _playerStateSub;

  // ── 2. Playback & Session State ────────────────────────────────────────────
  int _playSessionId = 0;
  int? _loadedSurah;
  int? _currentSurah;
  int? _currentAyah;
  int? _initialPlayAyah;
  bool _isContinuous = true;
  bool _isSeeking = false;

  // ── 3. Pause Retention State ───────────────────────────────────────────────
  bool _isPaused = false;
  int? _pausedSurah;
  int? _pausedAyah;
  int? _pausedWordIndex;

  // ── 4. Single-Word Playback State ──────────────────────────────────────────
  bool _isSingleWordMode = false;
  int? _singleWordStartMs;
  int? _singleWordEndMs;
  Timer? _wordEndTimer;

  // ── 5. Public Getters & Helpers ────────────────────────────────────────────
  bool get isPaused => _isPaused;
  bool get isSingleWordMode => _isSingleWordMode;

  /// Returns the streaming URL for a Surah audio file (64kbps mono MP3 from MP3Quran).
  static String getSurahAudioUrl(int surah) {
    final s = surah.toString().padLeft(3, '0');
    return '$mp3QuranAudioBaseUrl/$s-64k.mp3';
  }

  /// Lazy-initialized AudioPlayer instance with reactive event listeners.
  AudioPlayer get _audioPlayer {
    if (_player == null) {
      if (!kIsWeb) {
        AudioSession.instance.then((session) {
          session.configure(const AudioSessionConfiguration.music());
        }).catchError((_) {});
      }

      final p = AudioPlayer();

      // High-frequency position stream for silky 50fps word highlight synchronization
      _positionSub = p
          .createPositionStream(
            minPeriod: const Duration(milliseconds: 20),
            maxPeriod: const Duration(milliseconds: 40),
          )
          .listen(_handlePosition);

      // Processing state stream: drives UI loading and playing states
      _playerStateSub = p.playerStateStream.listen((state) {
        if (state.processingState == ProcessingState.completed) {
          _handleTrackComplete();
        } else {
          final isBuffering =
              state.processingState == ProcessingState.buffering ||
              state.processingState == ProcessingState.loading;
          final app = AppState.instance;
          if (isBuffering) {
            app.isAudioBuffering.value = true;
          } else {
            app.isAudioBuffering.value = false;
            if (state.playing) {
              app.isAudioPlaying.value = true;
            }
          }
        }
      });

      _player = p;
    }
    return _player!;
  }

  // ── 6. Core Preparation & Seeking Helper ───────────────────────────────────

  /// Centralized loader and seek engine.
  /// Prepares the Surah audio stream if needed, seeks with an `_isSeeking` lock,
  /// and validates session continuity.
  Future<bool> _prepareAndSeek({
    required int surah,
    required int targetMs,
    required int session,
  }) async {
    final player = _audioPlayer;

    if (_loadedSurah != surah) {
      _loadedSurah = surah;
      await player.setUrl(getSurahAudioUrl(surah));
    }
    if (session != _playSessionId) return false;

    _isSeeking = true;
    try {
      await player.seek(Duration(milliseconds: targetMs));
    } finally {
      _isSeeking = false;
    }

    return session == _playSessionId;
  }

  // ── 7. Public Playback API ─────────────────────────────────────────────────

  /// Plays the specified [ayah] in [surah] recited by Sheikh Al-Husary.
  ///
  /// - [continuous]: If true (outside Recording Mode), advances smoothly across subsequent Ayahs.
  ///                 If false (inside Recording Mode), plays only this single Ayah and stops.
  Future<void> play({
    required int surah,
    required int ayah,
    required bool continuous,
  }) async {
    final int session = ++_playSessionId;
    _cancelWordTimer();
    _isSingleWordMode = false;
    _singleWordStartMs = null;
    _singleWordEndMs = null;

    // Immediately silence any ongoing sound
    if (_player != null) {
      unawaited(_player!.pause().catchError((_) {}));
    }

    // Resume cleanly if this exact Ayah was paused
    if (_isPaused && _pausedSurah == surah && _pausedAyah == ayah && _player != null) {
      _isContinuous = continuous;
      AppState.instance.isContinuousPlayback.value = continuous;
      await resume();
      return;
    }

    _isPaused = false;
    _currentSurah = surah;
    _currentAyah = ayah;
    _initialPlayAyah = ayah;
    _isContinuous = continuous;

    final app = AppState.instance;
    app.activeAudioSurah.value = surah;
    app.activeAudioAyah.value = ayah;
    app.activeAudioWordIndex.value = null;
    app.isContinuousPlayback.value = continuous;
    app.isAudioBuffering.value = true;
    app.isAudioPlaying.value = false;

    try {
      final surahTiming = await QuranTimingService.instance.ensureSurahLoaded(surah);
      if (session != _playSessionId) return;

      if (surahTiming == null) {
        debugPrint('[QuranAudioService] Timings unavailable for Surah $surah.');
        _resetStateToStopped(
          triggerErrorBanner: true,
          errorReason: QuranTimingService.instance.lastFailureReason,
        );
        return;
      }

      final ayahTiming = surahTiming.getAyah(ayah);
      if (ayahTiming == null) {
        debugPrint('[QuranAudioService] Ayah $surah:$ayah timing not found.');
        _resetStateToStopped(triggerErrorBanner: true);
        return;
      }

      final bool isReady = await _prepareAndSeek(
        surah: surah,
        targetMs: ayahTiming.ayahStartMs,
        session: session,
      );
      if (!isReady) return;

      app.isAudioBuffering.value = false;
      app.isAudioPlaying.value = true;

      await _audioPlayer.play();
      _setWakelock(true);
    } catch (e, stack) {
      if (session == _playSessionId) {
        _handleError(e, stack, surah: surah, ayah: ayah);
      }
    }
  }

  /// Plays an individual word alone from Sheikh Al-Husary's recitation,
  /// highlighting only that word, and stopping immediately when the word completes.
  Future<void> playWord({
    required int surah,
    required int ayah,
    required int wordIndex,
  }) async {
    final int session = ++_playSessionId;
    _cancelWordTimer();
    _isSingleWordMode = true;
    _isPaused = false;
    _currentSurah = surah;
    _currentAyah = ayah;
    _isContinuous = false;

    // Immediately silence any ongoing sound
    if (_player != null) {
      unawaited(_player!.pause().catchError((_) {}));
    }

    final app = AppState.instance;
    app.activeAudioSurah.value = surah;
    app.activeAudioAyah.value = ayah;
    app.activeAudioWordIndex.value = wordIndex;
    app.isContinuousPlayback.value = false;
    app.isAudioBuffering.value = true;

    try {
      final surahTiming = await QuranTimingService.instance.ensureSurahLoaded(surah);
      if (session != _playSessionId) return;

      if (surahTiming == null) {
        debugPrint('[QuranAudioService] Timings unavailable for Surah $surah.');
        _resetStateToStopped(triggerErrorBanner: true);
        return;
      }

      final ayahTiming = surahTiming.getAyah(ayah);
      if (ayahTiming == null || ayahTiming.words.isEmpty) {
        debugPrint('[QuranAudioService] Ayah $surah:$ayah timing not found.');
        _resetStateToStopped(triggerErrorBanner: true);
        return;
      }

      final targetWord = ayahTiming.words.firstWhere(
        (w) => w.wordIndex == wordIndex,
        orElse: () => ayahTiming.words.first,
      );

      _singleWordStartMs = targetWord.startMs;
      _singleWordEndMs = targetWord.endMs;

      final int durationMs = (targetWord.endMs - targetWord.startMs).clamp(50, 15000);

      final bool isReady = await _prepareAndSeek(
        surah: surah,
        targetMs: targetWord.startMs,
        session: session,
      );
      if (!isReady) return;

      app.isAudioBuffering.value = false;
      app.isAudioPlaying.value = true;

      await _audioPlayer.play();

      // Arm safety fallback timer in case position stream drops
      _wordEndTimer = Timer(Duration(milliseconds: durationMs + 350), () {
        if (session == _playSessionId && _isSingleWordMode) {
          stopSingleWord(session);
        }
      });

      _setWakelock(true);
    } catch (e, stack) {
      if (session == _playSessionId) {
        _handleError(e, stack, surah: surah, ayah: ayah, wordIndex: wordIndex);
      }
    }
  }

  /// Stops single-word playback, pauses audio, and cleans up word highlight.
  void stopSingleWord([int? session]) {
    if (session != null && session != _playSessionId) return;
    _cancelWordTimer();
    _isSingleWordMode = false;
    _singleWordStartMs = null;
    _singleWordEndMs = null;

    try {
      _player?.pause();
    } catch (_) {}

    final app = AppState.instance;
    app.isAudioPlaying.value = false;
    app.isAudioBuffering.value = false;
    app.activeAudioWordIndex.value = null;
    app.activeAudioAyah.value = null;
    _setWakelock(false);
  }

  /// Pauses playback and keeps the paused word highlighted for calm resume.
  Future<void> pause() async {
    _cancelWordTimer();
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
    app.isAudioBuffering.value = false;
    _setWakelock(false);
  }

  /// Resumes playback from the exact paused word and millisecond.
  Future<void> resume() async {
    try {
      _isPaused = false;
      _currentSurah = _pausedSurah ?? _currentSurah;
      _currentAyah = _pausedAyah ?? _currentAyah;

      // Seek cleanly to paused word start timestamp
      if (_pausedWordIndex != null && _currentSurah != null && _currentAyah != null) {
        final timing = QuranTimingService.instance.getCachedAyahTiming(_currentSurah!, _currentAyah!);
        if (timing != null && timing.words.isNotEmpty) {
          final word = timing.words.firstWhere(
            (w) => w.wordIndex == _pausedWordIndex,
            orElse: () => timing.words.first,
          );
          _isSeeking = true;
          try {
            await _audioPlayer.seek(Duration(milliseconds: word.startMs));
          } finally {
            _isSeeking = false;
          }
          AppState.instance.activeAudioWordIndex.value = word.wordIndex;
        }
      }

      final app = AppState.instance;
      app.isAudioBuffering.value = false;
      app.isAudioPlaying.value = true;

      await _audioPlayer.play();
      _setWakelock(true);
    } catch (e, stack) {
      debugPrint('[QuranAudioService] Error resuming: $e');
      _handleError(e, stack);
    }
  }

  /// Completely stops playback and resets state.
  Future<void> stop() async {
    _playSessionId++;
    _cancelWordTimer();
    try {
      await _player?.stop();
    } catch (e) {
      debugPrint('[QuranAudioService] Error stopping: $e');
    }
    _resetStateToStopped();
  }

  // ── 8. Engine: Position & Boundary Tracking ────────────────────────────────

  /// Real-time position listener for word highlighting and Ayah transitions.
  void _handlePosition(Duration pos) {
    // ── Single Word Mode ──
    if (_isSingleWordMode) {
      if (_isSeeking) return;
      final int posMs = pos.inMilliseconds;
      if (posMs < (_singleWordStartMs ?? 0) - 100) return;
      if (_singleWordEndMs != null && posMs >= _singleWordEndMs!) {
        stopSingleWord(_playSessionId);
      }
      return;
    }

    // ── Full Ayah Playback Mode ──
    if (_isSeeking) return;
    if (!AppState.instance.isAudioPlaying.value && !(_player?.playing ?? false)) {
      return;
    }

    final surah = _currentSurah;
    if (surah == null) return;
    final int posMs = pos.inMilliseconds;

    final surahTiming = QuranTimingService.instance.getSurahTiming(surah);
    if (surahTiming == null) return;

    // Single source of truth: Binary search across Surah words
    final WordTiming? activeWord = surahTiming.findActiveWordAtMs(posMs);

    if (activeWord != null) {
      // ── Word is actively being recited ──

      // In non-continuous mode (Record Mode): stop immediately if crossing Ayah
      if (!_isContinuous && _initialPlayAyah != null && activeWord.ayah != _initialPlayAyah) {
        stop();
        return;
      }

      // In continuous mode: update active Ayah if audio naturally reached next Ayah
      if (activeWord.ayah != _currentAyah) {
        _currentAyah = activeWord.ayah;
        if (AppState.instance.activeAudioAyah.value != activeWord.ayah) {
          AppState.instance.activeAudioAyah.value = activeWord.ayah;
        }
      }

      // Update active word index
      if (AppState.instance.activeAudioWordIndex.value != activeWord.wordIndex) {
        AppState.instance.activeAudioWordIndex.value = activeWord.wordIndex;
      }
    } else {
      // ── Pause / breath between words or between Ayahs ──
      if (AppState.instance.activeAudioWordIndex.value != null) {
        AppState.instance.activeAudioWordIndex.value = null;
      }

      final int currentAyahNum = _currentAyah ?? (_initialPlayAyah ?? 1);
      final currentAyahTiming = surahTiming.getAyah(currentAyahNum);

      if (currentAyahTiming != null && posMs >= currentAyahTiming.ayahEndMs) {
        if (!_isContinuous) {
          // Single-Ayah mode (Record Mode): Ayah has fully completed
          stop();
          return;
        } else {
          // Continuous mode: advance to next Ayah during the breath
          final int maxAyah = surahTiming.ayahs.length;
          final int nextAyah = currentAyahNum + 1;
          if (nextAyah <= maxAyah) {
            _currentAyah = nextAyah;
            if (AppState.instance.activeAudioAyah.value != nextAyah) {
              AppState.instance.activeAudioAyah.value = nextAyah;
            }
          } else {
            // Reached end of Surah
            stop();
            return;
          }
        }
      }
    }
  }

  /// Handles track completion event when audio reaches the end of the file.
  void _handleTrackComplete() {
    if (_isSingleWordMode) {
      stopSingleWord(_playSessionId);
      return;
    }
    stop();
  }

  // ── 9. Cleanup & Error Handlers ────────────────────────────────────────────

  void _cancelWordTimer() {
    _wordEndTimer?.cancel();
    _wordEndTimer = null;
  }

  void _setWakelock(bool enable) {
    if (kIsWeb) return;
    try {
      if (enable) {
        WakelockPlus.enable();
      } else {
        WakelockPlus.disable();
      }
    } catch (_) {}
  }

  /// Internal cleanup routine guaranteeing consistent state.
  void _resetStateToStopped({
    bool triggerErrorBanner = false,
    AudioFailureReason? errorReason,
  }) {
    _cancelWordTimer();
    _isPaused = false;
    _pausedSurah = null;
    _pausedAyah = null;
    _pausedWordIndex = null;
    _isSingleWordMode = false;
    _singleWordStartMs = null;
    _singleWordEndMs = null;
    _initialPlayAyah = null;
    _currentSurah = null;
    _currentAyah = null;
    _isSeeking = false;
    _setWakelock(false);

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

  /// Centralized error handler that safely handles exceptions.
  void _handleError(
    Object error,
    StackTrace stack, {
    int? surah,
    int? ayah,
    int? wordIndex,
  }) {
    _loadedSurah = null; // Guarantee clean reconnect on retry
    final errStr = error.toString().toLowerCase();
    debugPrint('[QuranAudioService] Playback error: $error\n$stack');

    // MissingPluginException / platform channel issues
    if (errStr.contains('missingpluginexception') || errStr.contains('channel')) {
      debugPrint('[QuranAudioService] Platform audio plugin error. Needs fresh app restart.');
      _resetStateToStopped(triggerErrorBanner: false);
      return;
    }

    // Network disconnection / timeouts
    final bool isNetworkIssue = errStr.contains('socketexception') ||
        errStr.contains('timeoutexception') ||
        errStr.contains('network') ||
        errStr.contains('offline');

    _resetStateToStopped(
      triggerErrorBanner: true,
      errorReason: isNetworkIssue
          ? AudioFailureReason.networkOffline
          : AudioFailureReason.unknown,
    );
  }

  /// Releases player resources completely.
  Future<void> dispose() async {
    _cancelWordTimer();
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
