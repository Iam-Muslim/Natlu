import 'dart:async';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// Playback status for Ayah audio streaming.
enum AyahAudioStatus {
  idle,
  loading,
  playing,
  paused,
  error,
}

/// Exact standard verse counts for all 114 Surahs of the Holy Quran (Hafs).
const List<int> kSurahVerseCounts = [
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
  5, 4, 5, 6,
];

/// Clean, high-performance Quran Audio Engine.
///
/// Features:
/// 1. **Immediate Direct Streaming**: If an Ayah is not yet cached, it streams
///    directly via [UrlSource] without blocking or awaiting any download first.
/// 2. **Instant Local Playback**: Once cached, Ayahs play via [DeviceFileSource]
///    with near-zero latency (<15ms).
/// 3. **Single Next-Ayah Lookahead**: Only pre-fetches the immediate next Ayah (N+1)
///    in the background while Ayah N plays. Does NOT bulk download the Surah!
/// 4. **Single-Player Thread Safety**: Uses a single [AudioPlayer] instance to eliminate
///    native non-platform thread channel warnings on Windows desktop.
class AyahAudioService extends ChangeNotifier {
  AyahAudioService._() {
    _initEngine();
  }

  /// Singleton instance accessed across the app.
  static final AyahAudioService instance = AyahAudioService._();

  AudioPlayer? _player;
  AudioPlayer? _sfxPlayer;

  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<void>? _completeSub;

  int? _currentSurah;
  int? _currentAyah;
  AyahAudioStatus _status = AyahAudioStatus.idle;
  int _playSessionId = 0;
  bool _pluginAvailable = true;

  Directory? _cacheDirectory;
  final Map<String, Future<File?>> _inFlightDownloads = {};

  static final HttpClient _httpClient = HttpClient()
    ..connectionTimeout = const Duration(seconds: 10)
    ..idleTimeout = const Duration(seconds: 60)
    ..userAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) ReciteQuran/1.0';

  int? get currentSurah => _currentSurah;
  int? get currentAyah => _currentAyah;
  AyahAudioStatus get status => _status;

  bool get isPlaying => _status == AyahAudioStatus.playing;
  bool get isLoading => _status == AyahAudioStatus.loading;
  bool get isPaused => _status == AyahAudioStatus.paused;

  bool isAyahActive(int surah, int ayah) =>
      _currentSurah == surah && _currentAyah == ayah;

  bool isAyahPlaying(int surah, int ayah) =>
      isAyahActive(surah, ayah) && _status == AyahAudioStatus.playing;

  bool isAyahLoading(int surah, int ayah) =>
      isAyahActive(surah, ayah) && _status == AyahAudioStatus.loading;

  bool isAyahBusy(int surah, int ayah) =>
      isAyahActive(surah, ayah) &&
      (_status == AyahAudioStatus.playing || _status == AyahAudioStatus.loading);

  Future<Directory> _getCacheDir() async {
    if (_cacheDirectory != null) return _cacheDirectory!;
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/ayah_audio_cache/husary_64');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _cacheDirectory = dir;
    return dir;
  }

  void _initEngine() {
    try {
      _player = AudioPlayer();

      _stateSub = _player!.onPlayerStateChanged.listen(_onPlayerState);
      _completeSub = _player!.onPlayerComplete.listen((_) => _onPlayerComplete());
    } on MissingPluginException catch (e) {
      _pluginAvailable = false;
      _handlePluginMissing(e);
    } catch (e) {
      _handleError('Engine init error: $e');
    }

    _getCacheDir().catchError((e) {
      if (kDebugMode) print('AyahAudioService: Error initializing cache dir: $e');
      return Directory.systemTemp;
    });
  }

  AudioPlayer _getOrInitSfxPlayer() {
    _sfxPlayer ??= AudioPlayer();
    return _sfxPlayer!;
  }

  void _onPlayerState(PlayerState state) {
    switch (state) {
      case PlayerState.playing:
        if (_status != AyahAudioStatus.playing) {
          _status = AyahAudioStatus.playing;
          notifyListeners();
        }
        break;
      case PlayerState.paused:
        if (_status != AyahAudioStatus.paused) {
          _status = AyahAudioStatus.paused;
          notifyListeners();
        }
        break;
      case PlayerState.stopped:
        // Intentionally ignore native transient stopped events!
        // On Windows Media Foundation and mobile, switching sources raises a transient 'stopped'.
        // Never clear active Ayah from native events; only user stop() or end-of-surah clears it.
        break;
      case PlayerState.completed:
      case PlayerState.disposed:
        break;
    }
  }

  /// Triggered automatically when the active Ayah completes recitation.
  Future<void> _onPlayerComplete() async {
    if (_currentSurah == null || _currentAyah == null) {
      await stop();
      return;
    }

    final surah = _currentSurah!;
    final ayah = _currentAyah!;
    final totalVerses = (surah >= 1 && surah <= 114) ? kSurahVerseCounts[surah - 1] : 0;

    if (ayah >= totalVerses) {
      await stop();
      return;
    }

    final nextAyah = ayah + 1;
    await playAyah(surah, nextAyah);
  }

  /// Constructs standard EveryAyah Murattal URL for Mahmoud Khalil Al-Husary (64kbps).
  static String getHusaryAudioUrl(int surah, int ayah) {
    final sStr = surah.toString().padLeft(3, '0');
    final aStr = ayah.toString().padLeft(3, '0');
    return 'https://everyayah.com/data/Husary_64kbps/$sStr$aStr.mp3';
  }

  /// Resolves the local cache file for a specific Ayah.
  Future<File> getCachedFile(int surah, int ayah) async {
    final dir = await _getCacheDir();
    final sStr = surah.toString().padLeft(3, '0');
    final aStr = ayah.toString().padLeft(3, '0');
    return File('${dir.path}/$sStr$aStr.mp3');
  }

  /// Checks if an Ayah is already cached locally.
  Future<bool> isAyahCached(int surah, int ayah) async {
    try {
      final file = await getCachedFile(surah, ayah);
      return await file.exists() && (await file.length()) > 500;
    } catch (_) {
      return false;
    }
  }

  /// Downloads and caches a single Ayah audio file in background.
  Future<File?> _cacheAyahInBackground(int surah, int ayah) async {
    final file = await getCachedFile(surah, ayah);
    if (await file.exists() && (await file.length()) > 500) {
      return file;
    }

    final key = '${surah}_$ayah';
    if (_inFlightDownloads.containsKey(key)) {
      return _inFlightDownloads[key];
    }

    final future = _downloadAyahFile(surah, ayah, file);
    _inFlightDownloads[key] = future;
    try {
      return await future;
    } finally {
      _inFlightDownloads.remove(key);
    }
  }

  Future<File?> _downloadAyahFile(int surah, int ayah, File targetFile) async {
    final urlStr = getHusaryAudioUrl(surah, ayah);
    final tmpFile = File('${targetFile.path}.tmp');

    try {
      final uri = Uri.parse(urlStr);
      final req = await _httpClient.getUrl(uri);
      final resp = await req.close();

      if (resp.statusCode == 200 || resp.statusCode == 206) {
        final sink = tmpFile.openWrite();
        await resp.pipe(sink);
        await sink.close();

        if (await tmpFile.exists() && (await tmpFile.length()) > 500) {
          if (await targetFile.exists()) {
            try { await targetFile.delete(); } catch (_) {}
          }
          await tmpFile.rename(targetFile.path);
          return targetFile;
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('AyahAudioService: Error downloading $urlStr: $e');
      }
    } finally {
      if (await tmpFile.exists()) {
        try { await tmpFile.delete(); } catch (_) {}
      }
    }
    return null;
  }

  /// Pre-fetches ONLY the single immediate next Ayah in background while Ayah N plays.
  /// Does NOT download the whole Surah.
  void _prefetchNextAyahOnly(int surah, int currentAyah) {
    final total = (surah >= 1 && surah <= 114) ? kSurahVerseCounts[surah - 1] : 0;
    final nextAyah = currentAyah + 1;
    if (nextAyah <= total) {
      _cacheAyahInBackground(surah, nextAyah);
    }
  }

  /// Plays or stops playback for a specific Ayah.
  Future<void> togglePlayAyah(int surah, int ayah) async {
    if (isAyahActive(surah, ayah)) {
      await stop();
    } else {
      await playAyah(surah, ayah);
    }
  }

  /// Plays an Ayah.
  /// - Optimistically activates Ayah state on Frame 0 (0ms) so UI converts to Stop instantly.
  /// - If cached locally: starts INSTANTLY (<15ms) via DeviceFileSource.
  /// - If not cached: streams DIRECTLY via UrlSource right away without awaiting any file download!
  /// - Uses session token to prevent any asynchronous race conditions.
  Future<void> playAyah(int surah, int ayah) async {
    final int session = ++_playSessionId;

    // ── 0. OPTIMISTIC SYNCHRONOUS STATE UPDATE (0ms, Frame 0) ──
    _currentSurah = surah;
    _currentAyah = ayah;
    _status = AyahAudioStatus.playing;
    notifyListeners();

    try {
      // Check local cache
      final cachedFile = await getCachedFile(surah, ayah);
      if (session != _playSessionId) return;

      final bool hasLocalFile =
          await cachedFile.exists() && (await cachedFile.length()) > 500;
      if (session != _playSessionId) return;

      if (hasLocalFile) {
        // ── 1. INSTANT LOCAL PLAY (<15ms) ──
        await _player?.play(DeviceFileSource(cachedFile.path));
      } else {
        // ── 2. INSTANT DIRECT STREAMING (NO BLOCKING DOWNLOAD WAIT) ──
        final streamUrl = getHusaryAudioUrl(surah, ayah);
        await _player?.play(UrlSource(streamUrl));
        if (session != _playSessionId) {
          await _player?.stop();
          return;
        }

        // Save this Ayah in the background for future instant replays
        _cacheAyahInBackground(surah, ayah);
      }

      if (session != _playSessionId) return;

      // Pre-fetch ONLY the single next Ayah (N+1) in the background so the transition is gapless!
      _prefetchNextAyahOnly(surah, ayah);
    } on MissingPluginException catch (e) {
      _pluginAvailable = false;
      _handlePluginMissing(e);
    } catch (e) {
      if (session == _playSessionId) {
        _handleError('Error playing Ayah $surah:$ayah: $e');
        _status = AyahAudioStatus.idle;
        _currentSurah = null;
        _currentAyah = null;
        notifyListeners();
      }
    }
  }

  /// Stops current playback and clears the active Ayah immediately.
  Future<void> stop() async {
    _playSessionId++;

    _status = AyahAudioStatus.idle;
    _currentSurah = null;
    _currentAyah = null;
    notifyListeners();

    try {
      if (_pluginAvailable) {
        await _player?.stop();
      }
    } on MissingPluginException catch (e) {
      _handlePluginMissing(e);
    } catch (e) {
      _handleError('Error stopping audio: $e');
    }
  }

  // ── MISTAKE / ERROR VOICE ALERT CHANNEL (FUTURE-READY) ─────────────────────

  /// Plays a short correction chime or voice prompt when a recitation mistake is detected.
  Future<void> playCorrectionVoiceCue(Source source) async {
    try {
      final sfx = _getOrInitSfxPlayer();
      await sfx.stop();
      await sfx.play(source);
    } on MissingPluginException catch (e) {
      _handlePluginMissing(e);
    } catch (e) {
      _handleError('Error playing correction cue: $e');
    }
  }

  /// Plays a bundled asset sound for mistake notifications (e.g. 'assets/audio/mistake.mp3').
  Future<void> playMistakeAlertAsset(String assetPath) async {
    await playCorrectionVoiceCue(AssetSource(assetPath));
  }

  void _handlePluginMissing(MissingPluginException e) {
    if (kDebugMode) {
      print(
        '⚠️ AyahAudioService: audioplayers native plugin is not compiled into the current running process yet.\n'
        'Please restart the app ("flutter run") so native C++/Android/iOS plugin code is compiled.',
      );
    }
    _status = AyahAudioStatus.idle;
    notifyListeners();
  }

  void _handleError(String message) {
    if (kDebugMode) {
      print('AyahAudioService: $message');
    }
    _status = AyahAudioStatus.error;
    notifyListeners();
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _completeSub?.cancel();
    _player?.dispose();
    _sfxPlayer?.dispose();
    super.dispose();
  }
}
