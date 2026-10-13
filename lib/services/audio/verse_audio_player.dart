import 'dart:async';
import 'dart:developer' show log;
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import '../../state/app_state.dart';
import '../quran_timing_service.dart';

/// Verse and word audio playback service directly matching the professional architecture
/// and stability patterns of `quran_library` and `alquranalkareem`.
///
/// Architecture & Highlights:
/// - **Reciter**: Sheikh Mahmoud Khalil Al-Husary at **64kbps** (per-Ayah files from EveryAyah).
/// - **Zero Full-Surah Downloads**: Only downloads isolated, tiny per-Ayah files (~20-40 KB each).
/// - **Fast First-Time Local Disk Cache**: Caches each Ayah file to `quran_audio/Husary_64kbps/$s$a.mp3`.
///   Once cached, playback from disk is 100% instant (0ms latency, zero network wait).
/// - **Frame-Accurate Word Highlighting**: Synced with Quran.com Reciter 6 (Mahmoud Khalil Al-Husary)
///   0ms-relative word segments from [QuranTimingService].
/// - **Single Word Playback**: Plays any tapped word in Sheikh Al-Husary's voice by seeking to
///   the exact millisecond boundaries of that word in the cached Ayah file.
/// - **Background Pre-Warming**: While Ayah $N$ is actively playing, automatically pre-downloads
///   Ayah $N+1$ so continuous transitions between verses are seamless.
class VerseAudioPlayer {
  static const String everyAyahHusaryBaseUrl =
      'https://everyayah.com/data/Husary_64kbps';

  /// Canonical Ayah count for Surahs 1 to 114.
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
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<PlayerState>? _playerStateSub;

  int _sessionId = 0;
  String? _loadedAyahKey;
  int? _currentSurah;
  int? _currentAyah;
  bool _isContinuous = true;
  bool _isHandlingComplete = false;
  double _lastCompleteTime = 0.0;

  // Single word auditioning mode state
  bool _isSingleWordMode = false;
  int? _targetWordIndex;
  int? _targetWordEndMs;

  // Pause retention state
  bool _isPaused = false;
  int? _pausedSurah;
  int? _pausedAyah;
  int? _pausedWordIndex;

  bool get isPaused => _isPaused;
  int? get pausedSurah => _pausedSurah;
  int? get pausedAyah => _pausedAyah;
  int? get pausedWordIndex => _pausedWordIndex;
  bool get isPlaying => _player?.playing ?? false;
  bool get isSingleWordMode => _isSingleWordMode;
  int? get activeWordIndex => _targetWordIndex;
  int? get currentSurah => _currentSurah;
  int? get currentAyah => _currentAyah;

  /// Returns the per-Ayah 64kbps audio URL (Sheikh Mahmoud Khalil Al-Husary).
  static String getAyahAudioUrl(int surah, int ayah) {
    final s = surah.toString().padLeft(3, '0');
    final a = ayah.toString().padLeft(3, '0');
    return '$everyAyahHusaryBaseUrl/$s$a.mp3';
  }

  /// Backward-compatible URL helper.
  static String getSurahAudioUrl(int surah) => getAyahAudioUrl(surah, 1);

  /// Resolves the local disk cache file for an Ayah.
  static Future<File> getLocalAyahFile(int surah, int ayah) async {
    final dir = await getApplicationSupportDirectory();
    final s = surah.toString().padLeft(3, '0');
    final a = ayah.toString().padLeft(3, '0');
    final audioDir = Directory('${dir.path}/quran_audio/Husary_64kbps');
    if (!audioDir.existsSync()) {
      audioDir.createSync(recursive: true);
    }
    return File('${audioDir.path}/$s$a.mp3');
  }

  static final Set<String> _inFlightDownloads = {};

  /// Fast first-time cache: checks local disk first (0ms), otherwise returns the
  /// streaming URL immediately for zero-wait progressive playback while caching
  /// to disk in the background for instant future offline replays.
  static Future<String> ensureAyahDownloaded(int surah, int ayah) async {
    final url = getAyahAudioUrl(surah, ayah);
    if (kIsWeb) return url;

    try {
      final file = await getLocalAyahFile(surah, ayah);
      if (file.existsSync() && file.lengthSync() > 1024) {
        return file.path;
      }

      // Download and cache to disk in background; stream progressively right now
      unawaited(_downloadAndCacheAyah(surah, ayah, file));
      return url;
    } catch (_) {
      return url;
    }
  }

  static Future<void> _downloadAndCacheAyah(
    int surah,
    int ayah,
    File file,
  ) async {
    final key = '$surah:$ayah';
    if (_inFlightDownloads.contains(key)) return;
    _inFlightDownloads.add(key);

    final client = http.Client();
    try {
      final url = getAyahAudioUrl(surah, ayah);
      final res = await client.get(
        Uri.parse(url),
        headers: {
          if (!kIsWeb) 'User-Agent': 'Flutter/Natlu',
        },
      ).timeout(const Duration(seconds: 15));

      if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
        await file.writeAsBytes(res.bodyBytes, flush: true);
      }
    } catch (_) {
      // Background cache failure is non-fatal; playback continues via HTTP stream
    } finally {
      _inFlightDownloads.remove(key);
      client.close();
    }
  }

  /// Cancels all active subscriptions.
  void cancelAllSubscriptions() {
    _positionSub?.cancel();
    _positionSub = null;
    _playerStateSub?.cancel();
    _playerStateSub = null;
  }

  AudioPlayer get _audioPlayer {
    if (_player == null) {
      final p = AudioPlayer();
      _player = p;
      _ensureSubscriptions(p);
    } else {
      _ensureSubscriptions(_player!);
    }
    return _player!;
  }

  void _ensureSubscriptions(AudioPlayer p) {
    _positionSub ??= p.positionStream.listen(_handlePosition);

    _playerStateSub ??= p.playerStateStream.listen((state) {
      final app = AppState.instance;
      final isBuffering = state.processingState == ProcessingState.buffering ||
          state.processingState == ProcessingState.loading;
      app.isAudioBuffering.value = isBuffering;

      if (state.processingState == ProcessingState.completed) {
        _handleTrackComplete();
      } else if (state.playing) {
        app.isAudioPlaying.value = true;
        // When audio officially begins playing, activate word 0 if not yet set
        if (!_isSingleWordMode && app.activeAudioWordIndex.value == null) {
          app.activeAudioWordIndex.value = 0;
        }
      } else if (!state.playing && !isBuffering && (_isPaused || _currentAyah == null)) {
        app.isAudioPlaying.value = false;
      }
    });
  }

  /// Plays a single word in [ayah] of [surah] recited by Sheikh Mahmoud Khalil Al-Husary.
  Future<void> playWord({
    required int surah,
    required int ayah,
    required int wordIndex,
  }) async {
    final int session = ++_sessionId;

    _isSingleWordMode = true;
    _isPaused = false;
    _currentSurah = surah;
    _currentAyah = ayah;
    _targetWordIndex = wordIndex;
    _isContinuous = false;

    final app = AppState.instance;
    app.activeAudioSurah.value = surah;
    app.activeAudioAyah.value = ayah;
    app.activeAudioWordIndex.value = wordIndex;
    app.isContinuousPlayback.value = false;
    app.isAudioBuffering.value = true;
    app.isAudioPlaying.value = false;

    try {
      // 1. Ensure timings are loaded from Quran.com / disk cache
      final surahTiming =
          await QuranTimingService.instance.ensureSurahLoaded(surah);
      if (session != _sessionId) return;

      final ayahTiming = surahTiming?.getAyah(ayah);
      WordTiming? targetWord;
      if (ayahTiming != null && ayahTiming.words.isNotEmpty) {
        for (final w in ayahTiming.words) {
          if (w.wordIndex == wordIndex) {
            targetWord = w;
            break;
          }
        }
        if (targetWord == null &&
            wordIndex >= 0 &&
            wordIndex < ayahTiming.words.length) {
          targetWord = ayahTiming.words[wordIndex];
        }
      }

      final player = _audioPlayer;

      // 2. Fetch/resolve cached 64kbps Ayah file
      final audioPath = await ensureAyahDownloaded(surah, ayah);
      if (session != _sessionId) return;

      int startMs = 0;
      int endMs = 999999;
      if (targetWord != null) {
        startMs = targetWord.startMs;
        endMs = targetWord.endMs;
      }

      _targetWordEndMs = endMs;

      final ayahKey = '$surah:$ayah';
      if (_loadedAyahKey != ayahKey) {
        _loadedAyahKey = ayahKey;
        try {
          await player.stop();
        } catch (_) {}
        if (session != _sessionId) return;

        final AudioSource source = audioPath.startsWith('http')
            ? AudioSource.uri(Uri.parse(audioPath))
            : AudioSource.file(audioPath);

        await player.setAudioSource(
          source,
          initialPosition: Duration(milliseconds: startMs),
        );
      } else {
        await player.seek(Duration(milliseconds: startMs));
      }
      if (session != _sessionId) return;

      app.isAudioBuffering.value = false;
      app.isAudioPlaying.value = true;

      await player.play();
    } on PlatformException catch (e, stack) {
      if (session == _sessionId) {
        log('PlatformException in playWord: ${e.message}',
            name: 'VerseAudioPlayer', error: e, stackTrace: stack);
        _resetStopped(triggerError: true);
      }
    } catch (e, stack) {
      if (session == _sessionId) {
        log('Error playing word $surah:$ayah:$wordIndex: $e',
            name: 'VerseAudioPlayer', error: e, stackTrace: stack);
        _resetStopped(triggerError: true);
      }
    }
  }

  /// Plays [ayah] in [surah] recited by Sheikh Mahmoud Khalil Al-Husary (64kbps).
  Future<void> play({
    required int surah,
    required int ayah,
    required bool continuous,
  }) async {
    final int session = ++_sessionId;

    _isSingleWordMode = false;
    _targetWordIndex = null;
    _targetWordEndMs = null;

    // Fast-path resume if this exact Ayah was paused
    if (_player != null &&
        _currentSurah == surah &&
        _currentAyah == ayah &&
        _player!.processingState == ProcessingState.ready &&
        !_player!.playing) {
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
    // CRITICAL BUGFIX: Do NOT set word index to 0 while buffering!
    // Keep it null so no premature word highlighting occurs before sound plays.
    app.activeAudioWordIndex.value = null;
    app.isContinuousPlayback.value = continuous;
    app.isAudioBuffering.value = true;
    app.isAudioPlaying.value = false;

    // Pre-warm Surah timing in background
    unawaited(QuranTimingService.instance.ensureSurahLoaded(surah));

    try {
      final player = _audioPlayer;

      // 1. Ensure small 64kbps file is cached (~25KB)
      final audioPath = await ensureAyahDownloaded(surah, ayah);
      if (session != _sessionId) return;

      final ayahKey = '$surah:$ayah';
      if (_loadedAyahKey != ayahKey) {
        _loadedAyahKey = ayahKey;
        try {
          await player.stop();
        } catch (_) {}
        if (session != _sessionId) return;

        final AudioSource source = audioPath.startsWith('http')
            ? AudioSource.uri(Uri.parse(audioPath))
            : AudioSource.file(audioPath);

        await player.setAudioSource(source);
      } else {
        await player.seek(Duration.zero);
      }
      if (session != _sessionId) return;

      app.isAudioBuffering.value = false;
      app.isAudioPlaying.value = true;
      app.activeAudioWordIndex.value = 0; // Highlight first word as sound starts

      await player.play();

      // 2. Pre-cache the subsequent Ayah in background for gapless continuity
      if (continuous) {
        final maxAyahs = (surah >= 1 && surah <= 114)
            ? surahAyahCounts[surah - 1]
            : 286;
        if (ayah < maxAyahs) {
          unawaited(ensureAyahDownloaded(surah, ayah + 1));
        }
      }
    } catch (e, stack) {
      if (session == _sessionId) {
        log('Error playing $surah:$ayah: $e',
            name: 'VerseAudioPlayer', error: e, stackTrace: stack);
        _resetStopped(triggerError: true);
      }
    }
  }

  /// Real-time position listener for word-by-word tracking.
  void _handlePosition(Duration pos) {
    if (_isPaused || !isPlaying || !(_player?.playing ?? false)) return;
    if (_player?.processingState != ProcessingState.ready) return;

    final surah = _currentSurah;
    final ayah = _currentAyah;
    if (surah == null || ayah == null) return;

    final int posMs = pos.inMilliseconds;

    // Single-word mode: stop cleanly when target word end timestamp is reached
    if (_isSingleWordMode) {
      if (_targetWordEndMs != null && posMs >= _targetWordEndMs!) {
        stop();
      }
      return;
    }

    // Continuous recitation mode: lookup active word index
    final int? activeIdx = QuranTimingService.instance.getActiveWordIndexAtMs(
      surah: surah,
      ayah: ayah,
      positionMs: posMs,
    );

    if (activeIdx != null &&
        AppState.instance.activeAudioWordIndex.value != activeIdx) {
      AppState.instance.activeAudioWordIndex.value = activeIdx;
    }
  }

  void _handleTrackComplete() {
    final now = DateTime.now().millisecondsSinceEpoch / 1000.0;
    if (_isHandlingComplete || (now - _lastCompleteTime) < 0.2) return;
    _isHandlingComplete = true;
    _lastCompleteTime = now;

    try {
      if (_isSingleWordMode) {
        stop();
        return;
      }

      final surah = _currentSurah;
      final ayah = _currentAyah;

      if (_isContinuous && surah != null && ayah != null) {
        final int maxAyahs = (surah >= 1 && surah <= 114)
            ? surahAyahCounts[surah - 1]
            : 286;
        if (ayah < maxAyahs) {
          play(
            surah: surah,
            ayah: ayah + 1,
            continuous: true,
          );
          return;
        }
      }

      stop();
    } finally {
      _isHandlingComplete = false;
    }
  }

  /// Pauses playback and retains the current word highlight.
  Future<void> pause() async {
    try {
      _isPaused = true;
      _pausedSurah = _currentSurah;
      _pausedAyah = _currentAyah;
      _pausedWordIndex = AppState.instance.activeAudioWordIndex.value;
      await _player?.pause();
    } catch (e) {
      log('Error pausing: $e', name: 'VerseAudioPlayer');
    }
    final app = AppState.instance;
    app.isAudioPlaying.value = false;
    app.isAudioBuffering.value = false;
  }

  /// Resumes playback from the exact paused position.
  Future<void> resume() async {
    try {
      _isPaused = false;
      final app = AppState.instance;
      app.isAudioBuffering.value = false;
      app.isAudioPlaying.value = true;
      if (_pausedWordIndex != null) {
        app.activeAudioWordIndex.value = _pausedWordIndex;
      }
      await _audioPlayer.play();
    } catch (e, stack) {
      log('Error resuming: $e',
          name: 'VerseAudioPlayer', error: e, stackTrace: stack);
      _resetStopped(triggerError: true);
    }
  }

  /// Stops playback and clears all active audio states.
  Future<void> stop() async {
    _sessionId++;
    try {
      await _player?.stop();
    } catch (e) {
      log('Error stopping: $e', name: 'VerseAudioPlayer');
    }
    _resetStopped();
  }

  void _resetStopped({bool triggerError = false}) {
    _isPaused = false;
    _isSingleWordMode = false;
    _targetWordIndex = null;
    _targetWordEndMs = null;
    _pausedSurah = null;
    _pausedAyah = null;
    _pausedWordIndex = null;
    _currentSurah = null;
    _currentAyah = null;

    final app = AppState.instance;
    app.activeAudioWordIndex.value = null;
    app.activeAudioAyah.value = null;
    app.isAudioBuffering.value = false;
    app.isAudioPlaying.value = false;

    if (triggerError) {
      app.triggerAudioError(QuranTimingService.instance.lastFailureReason);
    }
  }

  Future<void> dispose() async {
    await stop();
    cancelAllSubscriptions();
    try {
      await _player?.dispose();
    } catch (_) {}
    _player = null;
    _loadedAyahKey = null;
  }
}
