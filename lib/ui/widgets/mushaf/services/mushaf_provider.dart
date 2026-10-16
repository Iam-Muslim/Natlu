import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:recite_quran/recite_quran.dart';

import '../../../../state/app_state.dart';
import '../classes/page.dart';
import '../classes/word.dart';

/// Clean data provider for the Mushaf layout.
/// Loads page lines JSON (from Svelte) and pairs them with aya_ui HafsSmart words.
class MushafProvider {
  MushafProvider._();
  static final MushafProvider instance = MushafProvider._();

  final Map<int, Page> _pages = {};
  final Map<String, int> _ayahToPage = {};
  final Map<String, List<String>> _ayahTokensMap = {};
  bool _isReady = false;
  bool _isLoading = false;
  Completer<void>? _loadingCompleter;

  bool isSyncingSurah = false;
  bool get isReady => _isReady;

  /// Pre-populates aya_ui tokens from decoded phoneme dataset
  void populateAllVerseWords(Map<String, dynamic> rawJson) {
    final versesMap = (rawJson['verses'] as Map<String, dynamic>?) ?? rawJson;
    final hizbRegex = RegExp(r'[۞۩]');
    versesMap.forEach((key, val) {
      if (val is Map) {
        final rawUthmani = val['aya_ui'] as String? ??
            val['uthmani'] as String? ??
            val['aya_text'] as String? ??
            '';
        final tokens = rawUthmani
            .trim()
            .split(' ')
            .map((w) => w.replaceAll(hizbRegex, '').trim())
            .where((s) => s.isNotEmpty)
            .toList();
        _ayahTokensMap[key] = tokens;
      }
    });
  }

  void preloadData({bool force = false}) {
    if ((_isReady && !force) || _isLoading) return;
    unawaited(loadData(force: force));
  }

  Future<void> loadData({bool force = false}) async {
    if (_isReady && !force) return;
    if (_isLoading) {
      await _loadingCompleter?.future;
      return;
    }
    _isLoading = true;
    _loadingCompleter = Completer<void>();

    try {
      final jsonStr = await rootBundle.loadString('assets/data/mushaf_pages.json');
      final rawPagesMap = json.decode(jsonStr) as Map<String, dynamic>;

      if (_ayahTokensMap.isEmpty) {
        final phonemeStr = await rootBundle.loadString(
          'packages/recite_quran/assets/model/ordered_quran_phonemes.json',
        );
        final rawPhonemes = json.decode(phonemeStr) as Map<String, dynamic>;
        populateAllVerseWords(rawPhonemes);
      }

      _pages.clear();
      _ayahToPage.clear();

      final Map<int, List<dynamic>> pageLinesMap = {};
      rawPagesMap.forEach((key, val) {
        final p = int.tryParse(key);
        if (p != null && val is List) {
          pageLinesMap[p] = List<dynamic>.from(val);
        }
      });

      // ============================================================================
      // CRITICAL ARCHITECTURAL RULE: SURAH BANNER & AYAH 1 CO-LOCATION
      // ============================================================================
      // In the King Fahd Medina Mushaf 1421H pagination, exactly 21 Surahs have their
      // decorative header banner positioned on line 15 (the very bottom line) of Page P,
      // while Ayah 1 of that Surah begins on line 1 of Page P+1:
      // (Surahs: 4, 10, 22, 23, 24, 26, 27, 32, 33, 37, 38, 45, 47, 53, 60, 64, 65, 80, 82, 86, 91).
      //
      // DESIGN INVARIANT:
      // - In Natlu Mushaf, the Surah header banner MUST ALWAYS be situated directly
      //   above Ayah 1 of the Surah.
      // - A Surah banner must NEVER be orphaned alone at the bottom of the previous page
      //   without its opening Ayah!
      //
      // The algorithm below detects this scenario and relocates the Surah header from
      // the bottom of Page P to index 0 of Page P+1 so that it renders right above Ayah 1.
      //
      // WARNING TO ANY DEVELOPER OR AI AGENT:
      // DO NOT REMOVE, BYPASS, OR ALTER THIS RELOCATION LOGIC!
      // ============================================================================
      for (int p = 1; p <= 603; p++) {
        final currentLines = pageLinesMap[p];
        final nextLines = pageLinesMap[p + 1];
        if (currentLines == null || nextLines == null || currentLines.isEmpty) continue;

        final lastLine = currentLines.last;
        if (lastLine is Map) {
          final t = lastLine['t'] as String? ?? lastLine['type'] as String?;
          if (t == 'header' || t == 'surah-header') {
            final surah = lastLine['s'] as int? ??
                int.tryParse(lastLine['surah']?.toString() ?? '0') ?? 0;
            final bool nextHasAyah1 = nextLines.any((l) {
              if (l is Map) {
                final w = l['w'] as List? ?? l['words'] as List?;
                if (w != null) {
                  return w.any((loc) => loc.toString().startsWith('$surah:1:'));
                }
              }
              return false;
            });

            if (nextHasAyah1) {
              currentLines.removeLast();
              nextLines.insert(0, lastLine);
            }
          }
        }
      }

      pageLinesMap.forEach((pageNum, linesList) {
        final page = Page.fromJSON(
          pageNumber: pageNum,
          rawLines: linesList,
          ayahTokensMap: _ayahTokensMap,
        );
        _pages[pageNum] = page;
        for (final ayahKey in page.ayahKeys) {
          _ayahToPage.putIfAbsent(ayahKey, () => pageNum);
        }
      });

      _isReady = true;
    } catch (e, st) {
      debugPrint('Error loading MushafProvider data: $e\n$st');
    } finally {
      _isLoading = false;
      _loadingCompleter?.complete();
    }
  }

  Page? getPage(int pageNumber) => _pages[pageNumber];

  (int surah, int ayah)? getFirstAyahOnPage(int pageNumber) =>
      _pages[pageNumber]?.firstAyah;

  int? getDominantSurahOnPage(int pageNumber) =>
      _pages[pageNumber]?.dominantSurah;

  bool isAyahOnPage({
    required int pageNumber,
    required int surah,
    required int ayah,
  }) =>
      _pages[pageNumber]?.ayahKeys.contains('$surah:$ayah') ?? false;

  int? getPageForAyah(int surah, int ayah) => _ayahToPage['$surah:$ayah'];

  MushafWordRef? getLastWordOnPage(int pageNumber) {
    final w = _pages[pageNumber]?.lastWord;
    if (w == null) return null;
    return MushafWordRef(
      surah: w.getSurahNumber() ?? 1,
      ayah: w.getVerseNumber() ?? 1,
      wordIndex1: w.getWordIndex0() + 1,
      wordIndex0: w.getWordIndex0(),
      text: w.text,
    );
  }

  Future<void> ensureActiveAyahOnCurrentPage({
    required HighlightingController controller,
    int? pageNumber,
  }) async {
    if (!_isReady) {
      await loadData();
    }
    final page = pageNumber ?? AppState.instance.currentMushafPage.value;
    final int? activeAyah = controller.activeAyah.value;
    final int targetSurah = controller.targetSurah != 0
        ? controller.targetSurah
        : AppState.instance.lastSurah;

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
          // If activeAyah.value is already equal to first.$2 (e.g. 1 == 1),
          // ValueNotifier setter will not notify listeners because oldValue == newValue.
          // Setting it to null first guarantees all listeners are notified of the new page's first ayah!
          if (controller.activeAyah.value == first.$2) {
            controller.activeAyah.value = null;
          }
          controller.setManualAyah(first.$1, first.$2);
          controller.globalRevision.value++;
          AppState.instance.saveLastPosition(first.$1, first.$2);
        } finally {
          isSyncingSurah = false;
        }
      }
    }
  }
}

/// Backward compatibility alias
typedef MushafRepository = MushafProvider;
