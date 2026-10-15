import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:recite_quran/recite_quran.dart';

import '../../../../state/app_state.dart';
import '../models/mushaf_models.dart';

/// Pure top-level function that runs inside a background isolate to decode
/// and index mushaf_pages.json into fast O(1) memory lookup structures.
MushafParsedData parseMushafJson(String jsonStr) {
  final Map<String, dynamic> rawMap = json.decode(jsonStr);

  final Map<int, List<Map<String, dynamic>>> pages = {};
  final Map<String, int> ayahMap = {};
  final Map<int, (int, int)> firstAyahMap = {};
  final Map<int, MushafWordRef> lastWordMap = {};
  final Map<int, Set<String>> pageAyahsMap = {};
  final Map<int, Set<int>> pageSurahsMap = {};
  final Map<int, int> dominantSurahMap = {};

  rawMap.forEach((key, val) {
    final pageNum = int.tryParse(key);
    if (pageNum != null && val is List) {
      final List<Map<String, dynamic>> lines = [];
      final Set<String> pageAyahs = {};
      final Set<int> pageSurahs = {};
      final Map<int, int> surahWordCounts = {};
      (int, int)? firstAyah;
      MushafWordRef? lastWord;

      for (final line in val) {
        if (line is Map) {
          final castedLine = Map<String, dynamic>.from(line);
          if (castedLine['t'] == 'header' && castedLine['s'] is int) {
            final s = castedLine['s'] as int;
            pageSurahs.add(s);
          } else if (castedLine['t'] == 'text' && castedLine['w'] is List) {
            final List<MushafWordRef> parsedWords = [];
            for (final loc in castedLine['w']) {
              final locStr = loc.toString();
              final colon1 = locStr.indexOf(':');
              final colon2 = locStr.indexOf(':', colon1 + 1);
              if (colon1 > 0 && colon2 > colon1) {
                final s = int.parse(locStr.substring(0, colon1));
                final a = int.parse(locStr.substring(colon1 + 1, colon2));
                final w1 = int.parse(locStr.substring(colon2 + 1));
                final ref = MushafWordRef(s, a, w1, w1 - 1);
                parsedWords.add(ref);
                final ayahKey = locStr.substring(0, colon2);
                ayahMap.putIfAbsent(ayahKey, () => pageNum);
                pageAyahs.add(ayahKey);
                pageSurahs.add(s);
                surahWordCounts[s] = (surahWordCounts[s] ?? 0) + 1;
                firstAyah ??= (s, a);
                lastWord = ref;
              }
            }
            castedLine['parsed_words'] = parsedWords;
          }
          lines.add(castedLine);
        }
      }
      pages[pageNum] = lines;
      pageAyahsMap[pageNum] = pageAyahs;
      pageSurahsMap[pageNum] = pageSurahs;
      if (firstAyah != null) firstAyahMap[pageNum] = firstAyah;
      if (lastWord != null) lastWordMap[pageNum] = lastWord;

      // Determine dominant Surah on this page (the Surah with majority of words):
      int? dominantSurah;
      int maxWords = -1;
      surahWordCounts.forEach((s, count) {
        if (count > maxWords) {
          maxWords = count;
          dominantSurah = s;
        }
      });
      if (dominantSurah != null) {
        dominantSurahMap[pageNum] = dominantSurah!;
      } else if (firstAyah != null) {
        dominantSurahMap[pageNum] = firstAyah.$1;
      }
    }
  });

  return MushafParsedData(
    pages: pages,
    ayahMap: ayahMap,
    firstAyahMap: firstAyahMap,
    lastWordMap: lastWordMap,
    pageAyahsMap: pageAyahsMap,
    pageSurahsMap: pageSurahsMap,
    dominantSurahMap: dominantSurahMap,
  );
}

/// High-performance singleton repository for Mushaf layout data.
///
/// Handles isolate background parsing, O(1) in-memory indices, and
/// page synchronization across the Quran recitation & audio session.
class MushafRepository {
  MushafRepository._();
  static final MushafRepository instance = MushafRepository._();

  /// Cached in-memory Mushaf layout data:
  /// pageNumber (1..604) -> list of line maps:
  /// - {'t': 'header', 's': 2, 'name': 'سورة البقرة'}
  /// - {'t': 'basmala'}
  /// - {'t': 'text', 'w': ['2:1:1', ...], 'parsed_words': List<MushafWordRef>}
  Map<int, List<Map<String, dynamic>>>? _mushafPagesCache;

  /// Fast lookup from "surah:ayah" to pageNumber
  Map<String, int>? _ayahToPageCache;

  /// Fast O(1) lookup: pageNumber -> first (surah, ayah)
  Map<int, (int, int)>? _pageFirstAyahCache;

  /// Fast O(1) lookup: pageNumber -> last MushafWordRef
  Map<int, MushafWordRef>? _pageLastWordCache;

  /// Fast O(1) lookup: pageNumber -> Set of all "surah:ayah" appearing on this page
  Map<int, Set<String>>? _pageAyahsCache;

  /// Fast O(1) lookup: pageNumber -> Set of all surahs appearing on this page
  Map<int, Set<int>>? _pageSurahsCache;

  /// Fast O(1) lookup: pageNumber -> dominant Surah on this page (by word count majority)
  Map<int, int>? _pageDominantSurahCache;

  /// Fast in-memory word cache for loaded verses: "surah:ayah" -> uthmaniWords
  final Map<String, List<String>> verseWordsMemoryCache = {};

  bool _isPreloading = false;
  Completer<void>? _loadingCompleter;

  /// Static synchronization flag to prevent re-entrant page navigation
  /// when synchronizing the selected Surah across page boundaries.
  bool isSyncingSurah = false;

  /// Whether the data has finished loading and caching into memory.
  bool get isReady => _mushafPagesCache != null;

  /// Raw pages cache
  Map<int, List<Map<String, dynamic>>>? get pagesCache => _mushafPagesCache;

  /// Preloads mushaf_pages.json in a background isolate on app startup.
  void preloadData() {
    if (_mushafPagesCache != null || _isPreloading) return;
    unawaited(loadMushafPagesJson());
  }

  /// Loads mushaf_pages.json if not already cached and builds instant O(1) lookup indices.
  Future<void> loadMushafPagesJson() async {
    if (_mushafPagesCache != null) return;
    if (_isPreloading) {
      await _loadingCompleter?.future;
      return;
    }
    _isPreloading = true;
    _loadingCompleter = Completer<void>();
    try {
      final jsonStr =
          await rootBundle.loadString('assets/data/mushaf_pages.json');
      final data = kIsWeb
          ? parseMushafJson(jsonStr)
          : await Isolate.run(() => parseMushafJson(jsonStr));

      _mushafPagesCache = data.pages;
      _ayahToPageCache = data.ayahMap;
      _pageFirstAyahCache = data.firstAyahMap;
      _pageLastWordCache = data.lastWordMap;
      _pageAyahsCache = data.pageAyahsMap;
      _pageSurahsCache = data.pageSurahsMap;
      _pageDominantSurahCache = data.dominantSurahMap;

      _attachWordsToRefs();
      unawaited(ensureVerseWordsLoaded());
    } catch (e) {
      debugPrint('Error loading mushaf_pages.json: $e');
    } finally {
      _isPreloading = false;
      _loadingCompleter?.complete();
    }
  }

  /// Ensures that all 6,236 ayah words are loaded into memory for zero-lag rendering.
  Future<void> ensureVerseWordsLoaded() async {
    if (verseWordsMemoryCache.length >= 6000) return;
    try {
      final phonemeStr = await rootBundle.loadString(
        'packages/recite_quran/assets/model/ordered_quran_phonemes.json',
      );
      final rawJson = json.decode(phonemeStr) as Map<String, dynamic>;
      populateAllVerseWords(rawJson);
    } catch (_) {}
  }

  /// Pre-populates all 6,236 ayah words from the decoded phoneme dataset into
  /// instant O(1) in-memory word lists, and attaches word text directly to all
  /// MushafWordRef instances across all 604 pages.
  void populateAllVerseWords(Map<String, dynamic> rawJson) {
    final versesMap = (rawJson['verses'] as Map<String, dynamic>?) ?? rawJson;
    final hizbRegex = RegExp(r'[۞۩]');
    versesMap.forEach((key, val) {
      if (val is Map) {
        final rawUthmani = val['aya_ui'] as String? ??
            val['uthmani'] as String? ??
            val['aya_text'] as String? ??
            '';
        final rawWords = rawUthmani.trim().split(' ');
        if (rawWords.length > 1 && val.containsKey('aya_ui')) {
          rawWords.removeLast();
        }
        final uthmaniWords = rawWords
            .map((w) => w.replaceAll(hizbRegex, ''))
            .where((s) => s.isNotEmpty)
            .toList();
        verseWordsMemoryCache[key] = uthmaniWords;
      }
    });

    _attachWordsToRefs();
  }

  void _attachWordsToRefs() {
    if (_mushafPagesCache == null || verseWordsMemoryCache.isEmpty) return;
    _mushafPagesCache!.forEach((pageNum, lines) {
      for (final line in lines) {
        if (line['parsed_words'] is List<MushafWordRef>) {
          final pw = line['parsed_words'] as List<MushafWordRef>;
          for (final ref in pw) {
            final words = verseWordsMemoryCache['${ref.surah}:${ref.ayah}'];
            if (words != null && ref.wordIndex0 < words.length) {
              ref.text = words[ref.wordIndex0];
            }
          }
        }
      }
    });
  }

  /// Returns the lines for [pageNumber].
  List<Map<String, dynamic>> getLinesForPage(int pageNumber) {
    return _mushafPagesCache?[pageNumber] ?? const [];
  }

  /// Returns the first (surah, ayah) appearing on [pageNumber] in O(1) time.
  (int surah, int ayah)? getFirstAyahOnPage(int pageNumber) {
    return _pageFirstAyahCache?[pageNumber];
  }

  /// Returns the dominant Surah on [pageNumber] in O(1) time.
  int? getDominantSurahOnPage(int pageNumber) {
    return _pageDominantSurahCache?[pageNumber] ??
        _pageFirstAyahCache?[pageNumber]?.$1;
  }

  /// Checks if the given Ayah is located on [pageNumber] in O(1) time.
  bool isAyahOnPage({
    required int pageNumber,
    required int surah,
    required int ayah,
  }) {
    return _pageAyahsCache?[pageNumber]?.contains('$surah:$ayah') ?? false;
  }

  /// Returns the very last word reference located on [pageNumber] in O(1) time.
  MushafWordRef? getLastWordOnPage(int pageNumber) {
    return _pageLastWordCache?[pageNumber];
  }

  /// Returns the page on which [surah:ayah] is located in O(1) time.
  int? getPageForAyah(int surah, int ayah) {
    return _ayahToPageCache?['$surah:$ayah'];
  }

  /// Returns the Set of all surahs appearing on [pageNumber].
  Set<int>? getPageSurahs(int pageNumber) {
    return _pageSurahsCache?[pageNumber];
  }

  /// Returns the Set of all "surah:ayah" keys appearing on [pageNumber].
  Set<String>? getPageAyahs(int pageNumber) {
    return _pageAyahsCache?[pageNumber];
  }

  /// Ensures that the active Ayah is on the visible page.
  /// If no Ayah on the current page is selected, automatically selects
  /// the first Ayah at the top of the current page.
  Future<void> ensureActiveAyahOnCurrentPage({
    required HighlightingController controller,
    int? pageNumber,
  }) async {
    if (_mushafPagesCache == null) {
      await loadMushafPagesJson();
    }
    final page = pageNumber ?? AppState.instance.currentMushafPage.value;
    final int? activeAyah = controller.activeAyah.value;
    final int targetSurah = controller.targetSurah;

    final bool isOnCurrentPage = activeAyah != null &&
        isAyahOnPage(pageNumber: page, surah: targetSurah, ayah: activeAyah);

    if (!isOnCurrentPage) {
      final first = getFirstAyahOnPage(page);
      if (first != null) {
        isSyncingSurah = true;
        try {
          if (controller.targetSurah != first.$1) {
            await controller.setTargetSurah(
              first.$1,
              preserveOtherSurahStates: true,
              clearTargetSurah: false,
            );
          }
          controller.setManualAyah(first.$1, first.$2);
          AppState.instance.saveLastPosition(first.$1, first.$2);
        } finally {
          isSyncingSurah = false;
        }
      }
    }
  }
}
