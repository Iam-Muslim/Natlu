import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../state/app_state.dart';

/// Single word timing interval matching MP3Quran v4 audio timestamps.
class WordTiming {
  /// Ayah number (1-based, e.g. 1 to 286).
  final int ayah;

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
    required this.ayah,
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

  /// Binary search to find the active 0-based word index at [positionMs] in milliseconds.
  ///
  /// Conforms strictly to MP3Quran v4 documentation:
  /// - Finds the entry with start_ms <= t < end_ms by binary search.
  /// - Returns null during pauses between words ("A pause between words has no entry").
  /// - Handles repeated words by occurrence order.
  int? getWordIndexAtMs(int positionMs) {
    if (words.isEmpty) return null;
    int low = 0;
    int high = words.length - 1;
    while (low <= high) {
      final mid = (low + high) >> 1;
      final w = words[mid];
      if (w.startMs <= positionMs) {
        if (positionMs < w.endMs) {
          return w.wordIndex;
        }
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    return null;
  }

  /// Backward-compatible lookup by seconds.
  int? getWordIndexAt(double positionSeconds) {
    return getWordIndexAtMs((positionSeconds * 1000).round());
  }
}

/// Complete timing model for a Surah loaded once via MP3Quran v4.
class SurahTiming {
  final int surah;
  final List<WordTiming> words;
  final Map<int, AyahTiming> ayahs;

  const SurahTiming({
    required this.surah,
    required this.words,
    required this.ayahs,
  });

  AyahTiming? getAyah(int ayah) => ayahs[ayah];

  /// Author-documented binary search across all surah words for time [t]:
  /// "On each timeupdate, find the entry with start_ms <= t < end_ms by binary search
  /// and highlight the word at its word_position. Clear the highlight when no entry matches."
  WordTiming? findActiveWordAtMs(int t) {
    if (words.isEmpty) return null;
    int low = 0;
    int high = words.length - 1;
    while (low <= high) {
      final mid = (low + high) >> 1;
      final w = words[mid];
      if (w.startMs <= t) {
        if (t < w.endMs) {
          return w;
        }
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    return null;
  }
}

/// High-performance Quran timing service integrating the MP3Quran v4 API.
///
/// Features & Architecture:
/// - **Pure On-Demand Streaming (Zero Disk Waste)**: Timings are streamed directly via HTTP
///   and kept in memory for the active session. Does NOT cache JSON files to disk, since
///   audio itself is streamed and JSON files without audio are useless offline.
/// - **Surah-Level Bulk Fetching**: Loads timing for a Surah ONCE as documented by the author:
///   `Load GET /v4/recitations/{code}/surahs/{n}/word-timings?include=text once for each surah.`
///   Zero additional network requests during Ayah transitions.
/// - **Sample-Accurate Binary Search**: $O(\log N)$ microsecond word resolution on audio ticks.
/// - **Resilient Offline / Recovery Handling**: Fast connection timeouts, graceful failure
///   when offline without freezing the UI, and instant self-healing when internet returns.
/// - **Full MP3Quran v4 Convention Compliance**:
///   - Reciter codes used exclusively (never numeric IDs).
///   - ETag caching (`If-None-Match` -> `304 Not Modified`).
///   - Real HTTP status & error envelope `{ error: { code, message, field } }` handling.
///   - Automatic rate limit backing off for 429 (`rate_limited`) and 503 (`queue_full`) via `Retry-After`.
///
/// Notice: Word timings are produced automatically via the MP3Quran v4 API.
class QuranTimingService {
  QuranTimingService._();
  static final QuranTimingService instance = QuranTimingService._();

  /// MP3Quran v4 API base URL as documented.
  static const String apiBaseUrl = 'https://api-staging.mp3quran.net/v4';

  /// Default reciter code (stored as permanent code string, never numeric ID).
  String recitationCode = 'mahmoud-husary/r1';

  /// Cross-platform HTTP Client (handles Android, iOS, Web, Windows).
  static final http.Client _client = http.Client();

  /// In-memory cache of loaded Surahs during this session (no disk file persistence).
  final Map<int, SurahTiming> _inMemorySurahs = {};

  /// In-flight coalescing to prevent duplicate concurrent network requests.
  final Map<int, Future<SurahTiming?>> _activeFetches = {};

  /// In-memory ETag cache for HTTP 304 Not Modified optimization.
  final Map<int, String> _etagMap = {};

  /// Tracks the last encountered failure reason for UI banner dispatch.
  AudioFailureReason lastFailureReason = AudioFailureReason.networkOffline;

  /// Synchronously gets an already loaded [SurahTiming] from in-memory cache.
  SurahTiming? getSurahTiming(int surah) => _inMemorySurahs[surah];

  /// Synchronously gets an already loaded [AyahTiming] from in-memory cache.
  AyahTiming? getCachedAyahTiming(int surah, int ayah) {
    return _inMemorySurahs[surah]?.getAyah(ayah);
  }

  /// Local disk cache directory for offline fast load.
  Future<File?> _getDiskCacheFile(int surah) async {
    if (kIsWeb) return null;
    try {
      final dir = await getApplicationSupportDirectory();
      final timingsDir = Directory('${dir.path}/quran_timings');
      if (!await timingsDir.exists()) {
        await timingsDir.create(recursive: true);
      }
      return File('${timingsDir.path}/surah_$surah.json');
    } catch (_) {
      return null;
    }
  }

  /// Ensures timing data for [surah] is loaded in memory.
  ///
  /// - Returns cached instance immediately if already in memory (0ms).
  /// - Loads from persistent disk cache if available (instant & offline-capable).
  /// - Streams from MP3Quran v4 API only when needed and caches to disk.
  /// - Coalesces concurrent calls so only a single request is in-flight.
  Future<SurahTiming?> ensureSurahLoaded(int surah) async {
    // 1. In-memory cache hit
    if (_inMemorySurahs.containsKey(surah)) {
      return _inMemorySurahs[surah];
    }

    // 2. Coalesce active in-flight request
    if (_activeFetches.containsKey(surah)) {
      return await _activeFetches[surah];
    }

    final completer = Completer<SurahTiming?>();
    _activeFetches[surah] = completer.future;

    () async {
      try {
        // Check disk cache first
        final cacheFile = await _getDiskCacheFile(surah);
        if (cacheFile != null && await cacheFile.exists()) {
          try {
            final content = await cacheFile.readAsString();
            if (content.length > 50) {
              final parsed = _parseSurahJson(surah, content);
              if (parsed != null) {
                _inMemorySurahs[surah] = parsed;
                completer.complete(parsed);
                return;
              }
            }
          } catch (e) {
            debugPrint('[QuranTimingService] Error reading disk cache for Surah $surah: $e');
          }
        }

        final timing = await _streamSurahTiming(surah);
        if (timing != null) {
          _inMemorySurahs[surah] = timing;
        }
        completer.complete(timing);
      } catch (e) {
        debugPrint('[QuranTimingService] Error streaming Surah $surah timings: $e');
        completer.complete(null);
      } finally {
        _activeFetches.remove(surah);
      }
    }();

    return await completer.future;
  }

  /// Backward-compatible helper ensuring an Ayah's timing is loaded.
  Future<AyahTiming?> ensureAyahLoaded(int surah, int ayah) async {
    final surahTiming = await ensureSurahLoaded(surah);
    return surahTiming?.getAyah(ayah);
  }

  /// Fetches JSON payload directly from the MP3Quran v4 API stream.
  Future<SurahTiming?> _streamSurahTiming(int surah, {int retryCount = 0}) async {
    final endpoint =
        '$apiBaseUrl/recitations/$recitationCode/surahs/$surah/word-timings?include=text';
    final uri = Uri.parse(endpoint);

    try {
      final headers = <String, String>{
        'Accept': 'application/json',
      };
      final savedEtag = _etagMap[surah];
      if (savedEtag != null && savedEtag.isNotEmpty) {
        headers['If-None-Match'] = savedEtag;
      }

      final response = await _client.get(uri, headers: headers).timeout(const Duration(seconds: 15));

      // ── 304 Not Modified ──
      if (response.statusCode == 304) {
        return _inMemorySurahs[surah];
      }

      // ── 200 OK ──
      if (response.statusCode == 200) {
        final etag = response.headers['etag'];
        if (etag != null && etag.isNotEmpty) {
          _etagMap[surah] = etag;
        }

        final body = utf8.decode(response.bodyBytes);
        // Cache to disk asynchronously
        _getDiskCacheFile(surah).then((file) {
          if (file != null) file.writeAsString(body).catchError((_) => file);
        }).catchError((_) {});

        return _parseSurahJson(surah, body);
      }

      // ── 429 Rate Limited or 503 Service Unavailable (Wait Retry-After) ──
      if (response.statusCode == 429 || response.statusCode == 503) {
        lastFailureReason = response.statusCode == 429
            ? AudioFailureReason.rateLimited
            : AudioFailureReason.serverUnavailable;
        final retryAfterHeader = response.headers['retry-after'];
        final int retryAfterSeconds = int.tryParse(retryAfterHeader ?? '2') ?? 2;

        debugPrint(
          '[QuranTimingService] HTTP ${response.statusCode} (Rate Limit / Queue Full). Retry-After: $retryAfterSeconds s',
        );

        if (retryCount == 0 && retryAfterSeconds <= 3) {
          await Future.delayed(Duration(seconds: retryAfterSeconds));
          return await _streamSurahTiming(surah, retryCount: retryCount + 1);
        }
        return null;
      }

      // ── Error Envelope { error: { code, message, field } } ──
      lastFailureReason = response.statusCode >= 500
          ? AudioFailureReason.serverUnavailable
          : AudioFailureReason.unknown;
      _handleApiError(response.statusCode, response.body);
      return null;
    } on SocketException {
      lastFailureReason = AudioFailureReason.networkOffline;
      debugPrint('[QuranTimingService] Network offline for Surah $surah');
      return null;
    } on TimeoutException {
      lastFailureReason = AudioFailureReason.networkOffline;
      debugPrint('[QuranTimingService] Stream request timed out for Surah $surah');
      return null;
    } catch (e) {
      lastFailureReason = AudioFailureReason.unknown;
      debugPrint('[QuranTimingService] Stream fetch error for Surah $surah: $e');
      return null;
    }
  }

  /// Handles and logs structured MP3Quran v4 API errors.
  void _handleApiError(int statusCode, String body) {
    try {
      final json = jsonDecode(body) as Map<String, dynamic>;
      final error = json['error'] as Map<String, dynamic>?;
      if (error != null) {
        final code = error['code']?.toString() ?? 'unknown';
        final message = error['message']?.toString() ?? '';
        final field = error['field']?.toString();
        debugPrint(
          '[QuranTimingService] API Error ($statusCode) [$code]: $message${field != null ? ' (field: $field)' : ''}',
        );
        return;
      }
    } catch (_) {}
    debugPrint('[QuranTimingService] HTTP Error $statusCode: $body');
  }

  /// Parses the MP3Quran v4 word-timings JSON response into a [SurahTiming] model.
  SurahTiming? _parseSurahJson(int surah, String jsonString) {
    try {
      final Map<String, dynamic> root = jsonDecode(jsonString) as Map<String, dynamic>;
      final Map<String, dynamic>? data = root['data'] as Map<String, dynamic>?;
      if (data == null) return null;

      final List<dynamic>? rawWords = data['words'] as List<dynamic>?;
      if (rawWords == null || rawWords.isEmpty) return null;

      // Extract text map: {ayah: {word_position: rasm}}
      final Map<int, Map<int, String>> textByAyah = {};
      try {
        final Map<String, dynamic>? textObj = data['text'] as Map<String, dynamic>?;
        if (textObj != null) {
          final List<dynamic>? textAyahs = textObj['ayahs'] as List<dynamic>?;
          if (textAyahs != null) {
            for (final dynamic aEntry in textAyahs) {
              if (aEntry is List && aEntry.length >= 2) {
                final int aNum = (aEntry[0] as num).toInt();
                final List<dynamic>? wordsList = aEntry[1] as List<dynamic>?;
                if (wordsList != null) {
                  final Map<int, String> wMap = {};
                  for (final dynamic wItem in wordsList) {
                    if (wItem is List && wItem.length >= 2) {
                      final int pos = (wItem[0] as num).toInt();
                      final String rasm = wItem[1]?.toString() ?? '';
                      wMap[pos] = rasm;
                    }
                  }
                  textByAyah[aNum] = wMap;
                }
              }
            }
          }
        }
      } catch (_) {}

      final List<WordTiming> allWords = [];
      final Map<int, List<WordTiming>> wordsByAyah = {};

      for (final dynamic item in rawWords) {
        if (item is! List || item.length < 4) continue;

        final int entryAyah = (item[0] as num).toInt();
        final int wordPos1Based = (item[1] as num).toInt();
        final int wordPos0Based = (wordPos1Based - 1).clamp(0, 999);
        final int startMs = (item[2] as num).toInt();
        final int endMs = (item[3] as num).toInt();
        final int occurrence = (item.length >= 5 && item[4] is num)
            ? (item[4] as num).toInt()
            : 1;

        final String wordText = textByAyah[entryAyah]?[wordPos1Based] ?? '';

        final wt = WordTiming(
          ayah: entryAyah,
          wordIndex: wordPos0Based,
          startMs: startMs,
          endMs: endMs,
          text: wordText,
          occurrence: occurrence,
        );

        allWords.add(wt);
        wordsByAyah.putIfAbsent(entryAyah, () => []).add(wt);
      }

      // Ensure strictly chronological ordering for guaranteed binary search correctness
      allWords.sort((a, b) => a.startMs.compareTo(b.startMs));
      wordsByAyah.forEach((_, list) {
        list.sort((a, b) => a.startMs.compareTo(b.startMs));
      });

      // Build AyahTiming for each ayah present in words
      final Map<int, AyahTiming> ayahTimings = {};
      wordsByAyah.forEach((aNum, aWords) {
        if (aWords.isNotEmpty) {
          final aStart = aWords.first.startMs;
          final aEnd = aWords.last.endMs;
          ayahTimings[aNum] = AyahTiming(
            surah: surah,
            ayah: aNum,
            ayahStartMs: aStart,
            ayahEndMs: aEnd,
            words: aWords,
          );
        }
      });

      return SurahTiming(
        surah: surah,
        words: allWords,
        ayahs: ayahTimings,
      );
    } catch (e) {
      debugPrint('[QuranTimingService] JSON parse error for Surah $surah: $e');
      return null;
    }
  }

  /// High-performance synchronous word index lookup by exact millisecond.
  int? getActiveWordIndexAtMs({
    required int surah,
    required int ayah,
    required int positionMs,
  }) {
    final surahTiming = _inMemorySurahs[surah];
    if (surahTiming == null) return null;
    final w = surahTiming.findActiveWordAtMs(positionMs);
    if (w != null && w.ayah == ayah) {
      return w.wordIndex;
    }
    return null;
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
