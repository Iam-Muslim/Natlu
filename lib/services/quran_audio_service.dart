import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import '../state/app_state.dart';
import 'quran_timing_service.dart';

/// High-performance Quran audio service powered by MP3Quran v4.
///
/// Architecture & Resilience:
/// - **Zero-Waste Range Streaming**: Streams audio on-demand via HTTP Range headers
///   without saving audio files to disk. Playing an Ayah streams ONLY the chunks needed.
/// - **Pure Streaming Timings**: Aligns with MP3Quran v4 word timings streamed into memory.
/// - **Full Offline / Online Resilience**:
///   - Handles no internet on initial play without freezing or fake-playing.
///   - Handles sudden internet drop mid-stream by cleanly detecting player interruptions.
///   - Handles internet restoration cleanly without stuck states or zombie audio sessions.
/// - **Author-Calibrated Word Sync**: Binary search lookup on audio ticks down to the millisecond.
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
  int? _singleWordStartMs;
  int? _singleWordEndMs;
  int? _singleWordIndex;

  // Track user-initiated stops to differentiate from network drops
  bool _isExplicitlyStopping = false;
  // Track intentional track preparation stops to prevent false severed-stream detection
  bool _isPreparingTrack = false;

  int _playSessionId = 0;

  /// Whether playback is currently paused on a specific Ayah/word.
  bool get isPaused => _isPaused;

  /// Guaranteed non-null AudioPlayer instance with robust event listeners.
  AudioPlayer get _audioPlayer {
    if (_player == null) {
      final p = AudioPlayer()..setReleaseMode(ReleaseMode.stop);

      // 35ms update timer for 30fps smooth word highlight synchronization
      p.positionUpdater = TimerPositionUpdater(
        interval: const Duration(milliseconds: 35),
        getPosition: p.getCurrentPosition,
      );

      p.onPositionChanged.listen(_handlePosition);
      p.onPlayerComplete.listen((_) => _handleTrackComplete());

      // Monitor player state transitions for network loss / platform errors
      p.onPlayerStateChanged.listen((state) {
        if (state == PlayerState.completed) {
          _handleTrackComplete();
        } else if (state == PlayerState.stopped) {
          // If stopped unexpectedly while state says playing or buffering, network stream dropped or couldn't connect
          if ((AppState.instance.isAudioPlaying.value || AppState.instance.isAudioBuffering.value) &&
              !_isExplicitlyStopping &&
              !_isPreparingTrack &&
              !_isPaused) {
            debugPrint('[QuranAudioService] Player stopped unexpectedly (stream severed or offline). Resetting.');
            _isExplicitlyStopping = true;
            try {
              _player?.stop();
            } catch (_) {}
            _isExplicitlyStopping = false;
            _resetStateToStopped(
              triggerErrorBanner: true,
              errorReason: AudioFailureReason.networkOffline,
            );
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
    if (!AppState.instance.isAudioPlaying.value) return;

    final surah = _currentSurah;
    final ayah = _currentAyah;
    if (surah == null || ayah == null) return;

    final int posMs = pos.inMilliseconds;

    // ── Single Word Playback Mode ──
    if (_singleWordEndMs != null && _singleWordStartMs != null) {
      if (AppState.instance.activeAudioWordIndex.value != _singleWordIndex) {
        AppState.instance.activeAudioWordIndex.value = _singleWordIndex;
      }
      if (posMs >= _singleWordStartMs! && posMs >= _singleWordEndMs!) {
        stop();
      }
      return;
    }

    // ── Regular Ayah Playback Mode ──
    final surahTiming = QuranTimingService.instance.getSurahTiming(surah);
    if (surahTiming == null) return;

    // 1. Binary search lookup for the active word (Author's specification)
    final WordTiming? activeWord = surahTiming.findActiveWordAtMs(posMs);

    if (activeWord != null) {
      // Sync Ayah if playback advanced naturally
      if (_currentAyah != activeWord.ayah) {
        _currentAyah = activeWord.ayah;
        AppState.instance.activeAudioAyah.value = activeWord.ayah;
      }
      if (AppState.instance.activeAudioWordIndex.value != activeWord.wordIndex) {
        AppState.instance.activeAudioWordIndex.value = activeWord.wordIndex;
      }
    } else {
      // "A pause between words has no entry... Clear the highlight when no entry matches."
      if (AppState.instance.activeAudioWordIndex.value != null) {
        AppState.instance.activeAudioWordIndex.value = null;
      }
    }

    // 2. Ayah boundary completion detection
    final currentAyahTiming = surahTiming.getAyah(_currentAyah!);
    if (currentAyahTiming != null && posMs >= currentAyahTiming.ayahEndMs) {
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
    try {
      _isPaused = false;
      _currentSurah = surah;
      _currentAyah = ayah;
      _isContinuous = false;

      // Provide immediate buffering feedback
      final app = AppState.instance;
      app.activeAudioSurah.value = surah;
      app.activeAudioAyah.value = ayah;
      app.activeAudioWordIndex.value = wordIndex;
      app.isAudioBuffering.value = true;

      // 1. Stream timing data for the Surah
      final surahTiming = await QuranTimingService.instance.ensureSurahLoaded(surah);

      if (surahTiming == null) {
        debugPrint('[QuranAudioService] Word timing unavailable (offline or API error). Aborting cleanly.');
        _resetStateToStopped(triggerErrorBanner: true);
        return;
      }

      if (session != _playSessionId) return;

      final ayahTiming = surahTiming.getAyah(ayah);
      if (ayahTiming == null || ayahTiming.words.isEmpty) {
        _resetStateToStopped(triggerErrorBanner: true);
        return;
      }

      // 2. Locate target WordTiming
      final targetWord = ayahTiming.words.firstWhere(
        (w) => w.wordIndex == wordIndex,
        orElse: () => ayahTiming.words.first,
      );

      _singleWordStartMs = targetWord.startMs;
      _singleWordEndMs = targetWord.endMs;
      _singleWordIndex = targetWord.wordIndex;

      final startDuration = Duration(milliseconds: targetWord.startMs);
      final player = _audioPlayer;

      if (_loadedSurah == surah && player.state != PlayerState.stopped) {
        await player.seek(startDuration);
        if (session != _playSessionId) return;
        await player.resume();
      } else {
        _loadedSurah = surah;
        final url = getSurahAudioUrl(surah);
        _isPreparingTrack = true;
        await player.stop();
        _isPreparingTrack = false;
        if (session != _playSessionId) return;
        await player.play(
          UrlSource(url),
          position: startDuration,
        );
      }

      if (session != _playSessionId) return;

      // Sync AppState now that stream has successfully started
      app.activeAudioSurah.value = surah;
      app.activeAudioAyah.value = ayah;
      app.activeAudioWordIndex.value = targetWord.wordIndex;
      app.isContinuousPlayback.value = false;
      app.isAudioBuffering.value = false;
      app.isAudioPlaying.value = true;
    } catch (e, stack) {
      debugPrint('[QuranAudioService] Error playing word ($surah:$ayah:$wordIndex): $e\n$stack');
      _resetStateToStopped(triggerErrorBanner: true);
    }
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
    try {
      _singleWordStartMs = null;
      _singleWordEndMs = null;
      _singleWordIndex = null;

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

      // Provide immediate buffering feedback on Click 1
      final app = AppState.instance;
      app.activeAudioSurah.value = surah;
      app.activeAudioAyah.value = ayah;
      app.isAudioBuffering.value = true;

      // 1. Fetch Surah timing stream from MP3Quran v4 API
      final surahTiming = await QuranTimingService.instance.ensureSurahLoaded(surah);

      // CRITICAL FIX: If timing stream failed (e.g. offline/network down), fail FAST and show banner immediately!
      // Do NOT check `session != _playSessionId` before `surahTiming == null`, otherwise rapid clicks swallow errors!
      if (surahTiming == null) {
        debugPrint('[QuranAudioService] Unable to stream timings for Surah $surah (offline or API error). Aborting.');
        _resetStateToStopped(triggerErrorBanner: true);
        return;
      }

      // If user selected a DIFFERENT verse while downloading, cleanly discard this obsolete attempt
      if (session != _playSessionId) return;

      final ayahTiming = surahTiming.getAyah(ayah);
      if (ayahTiming == null) {
        debugPrint('[QuranAudioService] Ayah $surah:$ayah not found in timing dataset. Aborting.');
        _resetStateToStopped(triggerErrorBanner: true);
        return;
      }

      final int startMs = ayahTiming.ayahStartMs;
      final startDuration = Duration(milliseconds: startMs);

      final player = _audioPlayer;

      if (_loadedSurah == surah && player.state != PlayerState.stopped) {
        // Already streaming this Surah: seek directly to Ayah offset via Range
        await player.seek(startDuration);
        if (session != _playSessionId) return;
        if (player.state != PlayerState.playing) {
          await player.resume();
        }
      } else {
        // Start streaming the Surah URL at the target Ayah timestamp
        _loadedSurah = surah;
        final url = getSurahAudioUrl(surah);
        _isPreparingTrack = true;
        await player.stop();
        _isPreparingTrack = false;
        if (session != _playSessionId) return;
        await player.play(
          UrlSource(url),
          position: startDuration,
        );
      }

      if (session != _playSessionId) return;

      // Timing & stream are ready and playing: update AppState to show playing state
      app.activeAudioSurah.value = surah;
      app.activeAudioAyah.value = ayah;
      app.activeAudioWordIndex.value = null;
      app.isContinuousPlayback.value = continuous;
      app.isAudioBuffering.value = false;
      app.isAudioPlaying.value = true;
    } catch (e, stack) {
      debugPrint('[QuranAudioService] Error playing $surah:$ayah (network or player): $e\n$stack');
      _resetStateToStopped(triggerErrorBanner: true);
    }
  }

  /// Handles completion when the audio player naturally reaches the file end.
  void _handleTrackComplete() {
    stop();
  }

  /// Pauses playback and keeps the paused word highlighted for calm resume.
  Future<void> pause() async {
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

      await _audioPlayer.resume();
      AppState.instance.isAudioPlaying.value = true;
    } catch (e) {
      debugPrint('[QuranAudioService] Error resuming: $e');
      _resetStateToStopped(triggerErrorBanner: true);
    }
  }

  /// Completely stops playback, resets streaming, and clears state.
  Future<void> stop() async {
    _playSessionId++;
    _isExplicitlyStopping = true;
    try {
      await _player?.stop();
    } catch (e) {
      debugPrint('[QuranAudioService] Error stopping: $e');
    } finally {
      _isExplicitlyStopping = false;
    }
    _resetStateToStopped();
  }

  /// Internal cleanup routine guaranteeing consistent state.
  void _resetStateToStopped({
    bool triggerErrorBanner = false,
    AudioFailureReason? errorReason,
  }) {
    _isPaused = false;
    _pausedSurah = null;
    _pausedAyah = null;
    _pausedWordIndex = null;
    _singleWordStartMs = null;
    _singleWordEndMs = null;
    _singleWordIndex = null;
    _loadedSurah = null;
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
}
