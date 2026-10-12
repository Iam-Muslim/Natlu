import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Single word timing interval matching MP3Quran v4 audio timestamps.
class WordTiming {
  /// 0-based word index inside the Ayah text.
  final int wordIndex;

  /// Start timestamp in milliseconds from the beginning of the Surah audio file.
  final int startMs;

  /// End timestamp in milliseconds from the beginning of the Surah audio file.
  final int endMs;

  /// Original word text from the timing dataset (Rasm Uthmani or Imlai).
  final String text;

  /// Occurrence counter (1 for first time heard, 2 for repetition, etc.).
  final int occurrence;

  const WordTiming({
    required this.wordIndex,
    required this.startMs,
    required this.endMs,
    required this.text,
    this.occurrence = 1,
  });

  /// Relative start timestamp in seconds (from the beginning of this Ayah).
  double getStartRelative(int ayahStartMs) =>
      ((startMs - ayahStartMs) / 1000.0).clamp(0.0, double.infinity);

  /// Relative end timestamp in seconds (from the beginning of this Ayah).
  double getEndRelative(int ayahStartMs) =>
      ((endMs - ayahStartMs) / 1000.0).clamp(0.0, double.infinity);
}

/// Timing model for a single Ayah with word-by-word intervals.
class AyahTiming {
  final int surah;
  final int ayah;
  final int ayahStartMs;
  final int ayahEndMs;
  final List<WordTiming> words;

  const AyahTiming({
    required this.surah,
    required this.ayah,
    required this.ayahStartMs,
    required this.ayahEndMs,
    required this.words,
  });

  /// Finds the active 0-based word index at [positionMs] in milliseconds.
  ///
  /// Keeps each word highlighted until the next word begins, delivering a calm,
  /// stable, flicker-free visual experience across pauses and breaths.
  int? getWordIndexAtMs(int positionMs) {
    if (words.isEmpty) return null;

    // 1. Before recitation starts: no word should be highlighted
    if (positionMs < words.first.startMs) {
      return null;
    }

    // 2. After the final word of this Ayah ends: no word should be highlighted
    if (positionMs > words.last.endMs + 100) {
      return null;
    }

    // 3. Highlight each word from its start until the next word starts
    for (int i = 0; i < words.length; i++) {
      final w = words[i];
      final int nextStart = (i + 1 < words.length)
          ? words[i + 1].startMs
          : (w.endMs + 100);

      if (positionMs >= w.startMs && positionMs < nextStart) {
        return w.wordIndex;
      }
    }

    return null;
  }

  /// Backward-compatible lookup by seconds.
  int? getWordIndexAt(double positionSeconds) {
    return getWordIndexAtMs((positionSeconds * 1000).round());
  }
}

/// Backward compatibility model for Surah timing queries.
class SurahTiming {
  final int surah;
  final Map<int, AyahTiming> ayahs;

  const SurahTiming({
    required this.surah,
    required this.ayahs,
  });

  AyahTiming? getAyah(int ayah) => ayahs[ayah];
}

/// High-performance Quran timing service integrating the MP3Quran v4 API.
///
/// Features:
/// - **Ayah-by-Ayah On-Demand Fetching**: Instead of downloading hundreds of kilobytes
///   for an entire Surah upfront, requests ONLY the single Ayah needed (~300 bytes),
///   saving >99% bandwidth.
/// - **100% Calibrated with MP3Quran Audio**: Word timestamps directly align with
///   MP3Quran's official audio files (`{surah}-64k.mp3`), delivering millisecond-accurate sync.
/// - **Permanent Disk Cache**: Caches each Ayah timing locally to
///   `{appDocDir}/quran_audio/timing/mp3quran_v4/{code}_{surah}_{ayah}.json` for instant offline replay.
/// - **Zero-Latency In-Memory Lookup**: Fast O(1) synchronous word index queries on every audio tick.
/// - **ETag Support**: Honors HTTP 304 Not Modified headers for bandwidth economy.
///
/// Notice: Word timings are produced automatically via the MP3Quran v4 API.
class QuranTimingService {
  QuranTimingService._();
  static final QuranTimingService instance = QuranTimingService._();

  /// MP3Quran v4 API base URL.
  static const String apiBaseUrl = 'https://api-staging.mp3quran.net/v4';

  /// Persistent Keep-Alive client avoiding socket exhaustion and handshake timeouts on Windows.
  static final HttpClient _client = HttpClient()
    ..idleTimeout = const Duration(minutes: 5)
    ..connectionTimeout = const Duration(seconds: 10);

  /// Default reciter code (stored as permanent code string, never numeric ID).
  String recitationCode = 'mahmoud-husary/r1';

  Directory? _timingDir;
  final Map<String, AyahTiming> _inMemoryAyahs = {};
  final Map<String, Future<AyahTiming?>> _activeFetches = {};
  final Map<String, String> _etagCache = {};

  /// Cache key for an Ayah.
  static String _ayahKey(int surah, int ayah) => '$surah:$ayah';

  /// Safe file naming for disk cache.
  String _getCacheFileName(int surah, int ayah) {
    final safeCode = recitationCode.replaceAll('/', '_').replaceAll(':', '_');
    return '${safeCode}_${surah.toString().padLeft(3, '0')}_${ayah.toString().padLeft(3, '0')}.json';
  }

  /// Directory for caching MP3Quran v4 timing data.
  Future<Directory> getTimingDirectory() async {
    if (_timingDir != null) return _timingDir!;
    final baseDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${baseDir.path}/quran_audio/timing/mp3quran_v4');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _timingDir = dir;
    return dir;
  }

  /// Local file for a cached Ayah timing.
  Future<File> getCachedFile(int surah, int ayah) async {
    final dir = await getTimingDirectory();
    return File('${dir.path}/${_getCacheFileName(surah, ayah)}');
  }

  /// Synchronously gets an already loaded [AyahTiming] from in-memory cache.
  AyahTiming? getCachedAyahTiming(int surah, int ayah) {
    return _inMemoryAyahs[_ayahKey(surah, ayah)];
  }

  /// Loads and caches word timing data for a single [surah] and [ayah] from MP3Quran v4.
  ///
  /// - Returns cached instance immediately if already in memory ($O(1)$).
  /// - Reads from local disk if cached previously.
  /// - Downloads on-demand from MP3Quran v4 API if not yet cached (~300 bytes payload).
  Future<AyahTiming?> ensureAyahLoaded(int surah, int ayah) async {
    final key = _ayahKey(surah, ayah);

    // 1. In-memory cache hit
    if (_inMemoryAyahs.containsKey(key)) {
      return _inMemoryAyahs[key];
    }

    // 2. Coalesce active in-flight network requests
    if (_activeFetches.containsKey(key)) {
      return await _activeFetches[key];
    }

    final completer = Completer<AyahTiming?>();
    _activeFetches[key] = completer.future;

    () async {
      try {
        final file = await getCachedFile(surah, ayah);

        // 3. Try local disk cache
        if (await file.exists() && (await file.length()) > 30) {
          try {
            final content = await file.readAsString();
            final parsed = _parseAyahJson(surah, ayah, content);
            if (parsed != null) {
              _inMemoryAyahs[key] = parsed;
              completer.complete(parsed);
              return;
            }
          } catch (e) {
            debugPrint('Disk cache read error for $key: $e');
          }
        }

        // 4. Fetch on-demand from MP3Quran v4 API with persistent client & retry
        final endpoint =
            '$apiBaseUrl/recitations/$recitationCode/surahs/$surah/word-timings?ayah=$ayah&include=text';
        final result = await _fetchWithRetry(endpoint, key);

        if (result == '304_NOT_MODIFIED' && await file.exists()) {
          final content = await file.readAsString();
          final parsed = _parseAyahJson(surah, ayah, content);
          if (parsed != null) {
            _inMemoryAyahs[key] = parsed;
            completer.complete(parsed);
            return;
          }
        }

        if (result != null && result != '304_NOT_MODIFIED') {
          final parsed = _parseAyahJson(surah, ayah, result);
          if (parsed != null) {
            _inMemoryAyahs[key] = parsed;

            // Persist to disk for offline replay
            try {
              final tempFile = File(
                '${file.path}.tmp_${DateTime.now().millisecondsSinceEpoch}',
              );
              await tempFile.writeAsString(result);
              if (await tempFile.exists()) {
                await tempFile.rename(file.path);
              }
            } catch (e) {
              debugPrint('Failed to save timing cache for $key: $e');
            }

            completer.complete(parsed);
            return;
          }
        }

        completer.complete(null);
      } catch (e) {
        debugPrint('Error loading timing for $surah:$ayah: $e');
        completer.complete(null);
      } finally {
        _activeFetches.remove(key);
      }
    }();

    return await completer.future;
  }

  /// Fetches JSON payload from the API with automatic retries and exponential backoff.
  Future<String?> _fetchWithRetry(String endpoint, String key) async {
    const int maxRetries = 3;
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        final request = await _client.getUrl(Uri.parse(endpoint));
        request.headers.set(HttpHeaders.acceptHeader, 'application/json');

        final cachedEtag = _etagCache[key];
        if (cachedEtag != null && cachedEtag.isNotEmpty) {
          request.headers.set(HttpHeaders.ifNoneMatchHeader, cachedEtag);
        }

        final response = await request.close();

        if (response.statusCode == HttpStatus.notModified) {
          await response.drain();
          return '304_NOT_MODIFIED';
        }

        if (response.statusCode == HttpStatus.ok) {
          final etag = response.headers.value(HttpHeaders.etagHeader);
          if (etag != null) {
            _etagCache[key] = etag;
          }
          final body = await response.transform(utf8.decoder).join();
          return body;
        }

        await response.drain();
        debugPrint('[QuranTimingService] HTTP ${response.statusCode} for $endpoint');
      } catch (e) {
        debugPrint('[QuranTimingService] Network attempt $attempt/$maxRetries failed for $key: $e');
        if (attempt < maxRetries) {
          await Future.delayed(Duration(milliseconds: 350 * attempt));
        }
      }
    }
    return null;
  }

  /// Backward-compatible helper to ensure a surah's initial ayah is loaded.
  Future<SurahTiming?> ensureSurahLoaded(int surah) async {
    final timing = await ensureAyahLoaded(surah, 1);
    if (timing == null) return null;
    return SurahTiming(
      surah: surah,
      ayahs: {1: timing},
    );
  }

  /// Parses the MP3Quran v4 word-timings JSON response into an [AyahTiming] model.
  ///
  /// Response format:
  /// `words`: `[[ayah, word_position, start_ms, end_ms, occurrence], ...]`
  /// `text`: `{"edition": "hafs", "ayahs": [[ayah, [[pos, rasm_uthmani, rasm_imlai], ...]]]}`
  AyahTiming? _parseAyahJson(int surah, int ayah, String jsonString) {
    try {
      final Map<String, dynamic> root = jsonDecode(jsonString) as Map<String, dynamic>;
      final Map<String, dynamic>? data = root['data'] as Map<String, dynamic>?;
      if (data == null) return null;

      final List<dynamic>? rawWords = data['words'] as List<dynamic>?;
      if (rawWords == null || rawWords.isEmpty) return null;

      // Extract text map if available: {word_position: text}
      final Map<int, String> textMap = {};
      try {
        final Map<String, dynamic>? textObj = data['text'] as Map<String, dynamic>?;
        if (textObj != null) {
          final List<dynamic>? textAyahs = textObj['ayahs'] as List<dynamic>?;
          if (textAyahs != null && textAyahs.isNotEmpty) {
            final List<dynamic>? wordList = textAyahs[0][1] as List<dynamic>?;
            if (wordList != null) {
              for (final dynamic item in wordList) {
                if (item is List && item.length >= 2) {
                  final int pos = (item[0] as num).toInt();
                  final String rasm = item[1]?.toString() ?? '';
                  textMap[pos] = rasm;
                }
              }
            }
          }
        }
      } catch (_) {}

      // Find the Ayah start in milliseconds from the first word
      final dynamic firstEntry = rawWords.first;
      if (firstEntry is! List || firstEntry.length < 4) return null;

      final int ayahStartMs = (firstEntry[2] as num).toInt();
      final dynamic lastEntry = rawWords.last;
      final int ayahEndMs = (lastEntry is List && lastEntry.length >= 4)
          ? (lastEntry[3] as num).toInt()
          : ayahStartMs;

      final List<WordTiming> words = [];

      for (final dynamic item in rawWords) {
        if (item is! List || item.length < 4) continue;

        final int entryAyah = (item[0] as num).toInt();
        if (entryAyah != ayah && entryAyah != 0) continue;

        final int wordPos1Based = (item[1] as num).toInt();
        final int wordPos0Based = (wordPos1Based - 1).clamp(0, 999);
        final int startMs = (item[2] as num).toInt();
        final int endMs = (item[3] as num).toInt();
        final int occurrence = (item.length >= 5 && item[4] is num)
            ? (item[4] as num).toInt()
            : 1;

        final String wordText = textMap[wordPos1Based] ?? '';

        words.add(WordTiming(
          wordIndex: wordPos0Based,
          startMs: startMs,
          endMs: endMs,
          text: wordText,
          occurrence: occurrence,
        ));
      }

      return AyahTiming(
        surah: surah,
        ayah: ayah,
        ayahStartMs: ayahStartMs,
        ayahEndMs: ayahEndMs,
        words: words,
      );
    } catch (e) {
      debugPrint('JSON parse error for MP3Quran v4 $surah:$ayah: $e');
      return null;
    }
  }

  /// High-performance synchronous word index lookup by exact millisecond.
  ///
  /// Returns the 0-based word index matching [positionMs] within the Surah audio,
  /// or `null` if before start, after finish, or data not yet loaded.
  int? getActiveWordIndexAtMs({
    required int surah,
    required int ayah,
    required int positionMs,
  }) {
    final key = _ayahKey(surah, ayah);
    final ayahData = _inMemoryAyahs[key];
    if (ayahData == null) return null;

    return ayahData.getWordIndexAtMs(positionMs);
  }

  /// Backward-compatible lookup by seconds.
  int? getActiveWordIndex({
    required int surah,
    required int ayah,
    required double positionSeconds,
  }) {
    return getActiveWordIndexAtMs(
      surah: surah,
      ayah: ayah,
      positionMs: (positionSeconds * 1000).round(),
    );
  }
}
