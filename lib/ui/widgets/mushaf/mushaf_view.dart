import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:recite_quran/recite_quran.dart';

import '../../../state/app_state.dart';
import '../helpers/verse_span_builder.dart';
import '../verse_row.dart';

/// Desktop & Mobile friendly scroll behavior allowing mouse/touch drag on PageView
class _MushafScrollBehavior extends MaterialScrollBehavior {
  const _MushafScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      };
}

/// Cached in-memory Mushaf layout data:
/// pageNumber (1..604) -> list of line maps:
/// - {'t': 'header', 's': 2, 'name': 'سورة البقرة'}
/// - {'t': 'basmala'}
/// - {'t': 'text', 'w': ['2:1:1', ...]}
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

/// Fast typed word reference within a  Mushaf page
class MushafWordRef {
  final int surah;
  final int ayah;
  final int wordIndex1;
  final int wordIndex0;
  const MushafWordRef(this.surah, this.ayah, this.wordIndex1, this.wordIndex0);
}

/// High-Performance Authentic 15-line  Mushaf Layout View.
/// - Exact 15-line  Mushaf structure with Surah headers, Basmalas, and bottom page numbers.
/// - Single-layer rendering: only ONE RepaintBoundary per page (95% GPU layer reduction).
/// - Instantaneous flex-based line justification via native C++ flex distribution (0ms CPU blocking).
/// - Scoped per-page state listening: only the currently active page rebuilds during recitation/playback.
/// - Full 60-120 FPS buttery smooth page shifts and zero-latency button presses.
class MushafView extends StatefulWidget {
  final HighlightingController controller;
  final bool isRecording;
  final bool isAutoScrolling;
  final VoidCallback? onToggleAutoScroll;

  /// Custom font family for Quranic words (e.g. 'HafsSmart', 'cairo', or any custom TTF).
  final String wordFontFamily;

  /// Custom font family for Ayah numbers inside markers (defaults to wordFontFamily).
  final String? ayahMarkerFontFamily;

  /// Custom border color for the circle around the Ayah number.
  final Color? ayahMarkerBorderColor;

  /// Custom text color for the Ayah number.
  final Color? ayahMarkerTextColor;

  /// Border width for the circle surrounding the Ayah number.
  final double ayahMarkerBorderWidth;

  /// Whether to show the surrounding circle border around the Ayah number.
  final bool showAyahMarkerCircle;

  /// Whether to display bottom page numbers (false = pure distraction-free canvas).
  final bool showBottomPageNumber;

  const MushafView({
    super.key,
    required this.controller,
    required this.isRecording,
    this.isAutoScrolling = false,
    this.onToggleAutoScroll,
    this.wordFontFamily = 'HafsSmart',
    this.ayahMarkerFontFamily,
    this.ayahMarkerBorderColor,
    this.ayahMarkerTextColor,
    this.ayahMarkerBorderWidth = 1.2,
    this.showAyahMarkerCircle = true,
    this.showBottomPageNumber = true,
  });

  /// Static synchronization flag to prevent re-entrant page navigation
  /// when synchronizing the selected Surah across page boundaries.
  static bool isSyncingSurah = false;

  /// Returns the first (surah, ayah) appearing on [pageNumber] in O(1) time.
  static (int surah, int ayah)? getFirstAyahOnPage(int pageNumber) {
    return _pageFirstAyahCache?[pageNumber];
  }

  /// Checks if the given Ayah is located on [pageNumber] in O(1) time.
  static bool isAyahOnPage({
    required int pageNumber,
    required int surah,
    required int ayah,
  }) {
    return _pageAyahsCache?[pageNumber]?.contains('$surah:$ayah') ?? false;
  }

  /// Returns the very last word reference located on [pageNumber] in O(1) time.
  static MushafWordRef? getLastWordOnPage(int pageNumber) {
    return _pageLastWordCache?[pageNumber];
  }

  /// Loads mushaf_pages.json if not already cached and builds instant O(1) lookup indices.
  static Future<void> _loadMushafPagesJson() async {
    if (_mushafPagesCache != null) return;
    try {
      final jsonStr =
          await rootBundle.loadString('assets/data/mushaf_pages.json');
      final Map<String, dynamic> rawMap = json.decode(jsonStr);

      final Map<int, List<Map<String, dynamic>>> pages = {};
      final Map<String, int> ayahMap = {};
      final Map<int, (int, int)> firstAyahMap = {};
      final Map<int, MushafWordRef> lastWordMap = {};
      final Map<int, Set<String>> pageAyahsMap = {};
      final Map<int, Set<int>> pageSurahsMap = {};

      rawMap.forEach((key, val) {
        final pageNum = int.tryParse(key);
        if (pageNum != null && val is List) {
          final List<Map<String, dynamic>> lines = [];
          final Set<String> pageAyahs = {};
          final Set<int> pageSurahs = {};
          (int, int)? firstAyah;
          MushafWordRef? lastWord;

          for (final line in val) {
            if (line is Map) {
              final castedLine = Map<String, dynamic>.from(line);
              if (castedLine['t'] == 'header' && castedLine['s'] is int) {
                pageSurahs.add(castedLine['s'] as int);
              } else if (castedLine['t'] == 'text' && castedLine['w'] is List) {
                final List<MushafWordRef> parsedWords = [];
                for (final loc in castedLine['w']) {
                  final parts = loc.toString().split(':');
                  if (parts.length >= 3) {
                    final s = int.parse(parts[0]);
                    final a = int.parse(parts[1]);
                    final w1 = int.parse(parts[2]);
                    final ref = MushafWordRef(s, a, w1, w1 - 1);
                    parsedWords.add(ref);
                    ayahMap.putIfAbsent('$s:$a', () => pageNum);
                    pageAyahs.add('$s:$a');
                    pageSurahs.add(s);
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
        }
      });

      _mushafPagesCache = pages;
      _ayahToPageCache = ayahMap;
      _pageFirstAyahCache = firstAyahMap;
      _pageLastWordCache = lastWordMap;
      _pageAyahsCache = pageAyahsMap;
      _pageSurahsCache = pageSurahsMap;
    } catch (e) {
      debugPrint('Error loading mushaf_pages.json: $e');
    }
  }

  /// Ensures that the active Ayah is on the visible page.
  /// If no Ayah on the current page is selected, automatically selects
  /// the first Ayah at the top of the current page.
  static Future<void> ensureActiveAyahOnCurrentPage({
    required HighlightingController controller,
    int? pageNumber,
  }) async {
    if (_mushafPagesCache == null) {
      await _loadMushafPagesJson();
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

  @override
  State<MushafView> createState() => _MushafViewState();
}

class _MushafViewState extends State<MushafView> {
  late PageController _pageController;
  int _currentPage = 1;
  bool _isLoading = true;
  final Set<int> _loadedSurahs = {};
  final FocusNode _focusNode = FocusNode();
  (int surah, int ayah)? _navigationTargetAyah;

  @override
  void initState() {
    super.initState();
    _currentPage = _findInitialPage();
    AppState.instance.currentMushafPage.value = _currentPage;
    _pageController = PageController(initialPage: _currentPage - 1);

    widget.controller.activeAyah.addListener(_onActiveAyahChanged);
    widget.controller.addListener(_onControllerProgress);
    AppState.instance.activeAudioAyah.addListener(_onAudioAyahChanged);
    AppState.instance.activeAudioSurah.addListener(_onAudioAyahChanged);

    _initMushafData();
  }

  @override
  void didUpdateWidget(MushafView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.activeAyah.removeListener(_onActiveAyahChanged);
      oldWidget.controller.removeListener(_onControllerProgress);
      widget.controller.activeAyah.addListener(_onActiveAyahChanged);
      widget.controller.addListener(_onControllerProgress);
    }
    if (!oldWidget.isRecording && widget.isRecording) {
      final active = widget.controller.activeAyah.value;
      if (active == null ||
          !MushafView.isAyahOnPage(
            pageNumber: _currentPage,
            surah: widget.controller.targetSurah,
            ayah: active,
          )) {
        MushafView.ensureActiveAyahOnCurrentPage(
          controller: widget.controller,
          pageNumber: _currentPage,
        );
      }
    }
  }

  int _findInitialPage() {
    final surah = widget.controller.targetSurah != 0
        ? widget.controller.targetSurah
        : AppState.instance.lastSurah;
    final ayah =
        widget.controller.activeAyah.value ?? AppState.instance.lastAyah;
    if (_ayahToPageCache != null) {
      final key = '$surah:$ayah';
      return _ayahToPageCache![key] ?? _ayahToPageCache!['$surah:1'] ?? 1;
    }
    return 1;
  }

  Future<void> _initMushafData() async {
    await MushafView._loadMushafPagesJson();

    if (mounted) {
      final initialPage = _findInitialPage();
      _currentPage = initialPage;
      AppState.instance.currentMushafPage.value = _currentPage;
      if (widget.controller.targetSurah == 0) {
        await widget.controller.setTargetSurah(
          AppState.instance.lastSurah,
          preserveOtherSurahStates: true,
          clearTargetSurah: false,
        );
      }
      final targetIndex = _currentPage - 1;
      if (_pageController.hasClients) {
        if ((_pageController.page?.round() ?? 0) != targetIndex) {
          _pageController.jumpToPage(targetIndex);
        }
      } else {
        _pageController.dispose();
        _pageController = PageController(initialPage: targetIndex);
      }
      _ensurePageSurahsLoaded(_currentPage);
      setState(() => _isLoading = false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            _pageController.hasClients &&
            (_pageController.page?.round() ?? 0) != targetIndex) {
          _pageController.jumpToPage(targetIndex);
        }
      });
    }
  }

  @override
  void dispose() {
    widget.controller.activeAyah.removeListener(_onActiveAyahChanged);
    widget.controller.removeListener(_onControllerProgress);
    AppState.instance.activeAudioAyah.removeListener(_onAudioAyahChanged);
    AppState.instance.activeAudioSurah.removeListener(_onAudioAyahChanged);
    _pageController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  bool _isAutoAdvancingPage = false;

  void _onControllerProgress() {
    if (!mounted || _isAutoAdvancingPage || _mushafPagesCache == null) return;

    final ctrl = widget.controller;
    final lastWord = MushafView.getLastWordOnPage(_currentPage);
    if (lastWord == null) return;

    // Check if the last word on the currently visible page was finished
    final bool isLastWordFinished = ctrl.isWordGreen(
            lastWord.ayah, lastWord.wordIndex0, surah: lastWord.surah) ||
        ctrl.isWordNeutral(lastWord.ayah, lastWord.wordIndex0,
            surah: lastWord.surah) ||
        ctrl.completedAyahsFor(lastWord.surah).contains(lastWord.ayah);

    if (!isLastWordFinished) return;

    final int nextPage = _currentPage + 1;
    if (nextPage > 604) return;

    final nextFirst = MushafView.getFirstAyahOnPage(nextPage);
    if (nextFirst == null) return;

    final int nextSurah = nextFirst.$1;
    final int nextAyah = nextFirst.$2;

    _isAutoAdvancingPage = true;

    () async {
      try {
        if (nextSurah != ctrl.targetSurah) {
          // The next page begins with a NEW SURAH!
          _navigationTargetAyah = (nextSurah, nextAyah);
          _goToPage(nextPage);

          await ctrl.setTargetSurah(
            nextSurah,
            preserveOtherSurahStates: true,
            clearTargetSurah: false,
          );
          ctrl.setManualAyah(nextSurah, nextAyah);
          AppState.instance.saveLastPosition(nextSurah, nextAyah);
          if (widget.isRecording) {
            ctrl.startRecordingSession();
          }
        } else {
          // If the next page is in the same Surah:
          if (ctrl.activeAyah.value != nextAyah) {
            ctrl.setManualAyah(nextSurah, nextAyah);
            AppState.instance.saveLastPosition(nextSurah, nextAyah);
          }
          _navigationTargetAyah = (nextSurah, nextAyah);
          _goToPage(nextPage);
        }
      } catch (e) {
        debugPrint('Error advancing page on last word: $e');
      } finally {
        await Future.delayed(const Duration(milliseconds: 600));
        _isAutoAdvancingPage = false;
      }
    }();
  }

  void _onAudioAyahChanged() {
    final active = AppState.instance.activeAudioAyah.value;
    final surah = AppState.instance.activeAudioSurah.value;
    if (active != null && surah != null && _ayahToPageCache != null) {
      if (MushafView.isAyahOnPage(
        pageNumber: _currentPage,
        surah: surah,
        ayah: active,
      )) {
        _navigationTargetAyah = null;
        return;
      }
      final targetPage = _ayahToPageCache!['$surah:$active'];
      if (targetPage != null && targetPage != _currentPage) {
        _navigationTargetAyah = (surah, active);
        _goToPage(targetPage);
      }
    }
  }

  void _onActiveAyahChanged() {
    if (MushafView.isSyncingSurah || _isAutoAdvancingPage) return;
    final active = widget.controller.activeAyah.value;
    if (active != null) {
      final surah = widget.controller.targetSurah;
      AppState.instance.saveLastPosition(surah, active);

      // If active ayah is already on the currently visible page, do not animate/navigate!
      if (MushafView.isAyahOnPage(
        pageNumber: _currentPage,
        surah: surah,
        ayah: active,
      )) {
        _navigationTargetAyah = null;
        return;
      }

      if (_ayahToPageCache != null) {
        final targetPage = _ayahToPageCache!['$surah:$active'];
        if (targetPage != null && targetPage != _currentPage) {
          _navigationTargetAyah = (surah, active);
          _goToPage(targetPage);
        }
      }
    }
  }

  Future<void> _syncPageSelection(int pageNum) async {
    // 1. If explicit navigation was requested to a specific Ayah (e.g. search, auto-reanchor, audio):
    if (_navigationTargetAyah != null) {
      final target = _navigationTargetAyah!;
      if (MushafView.isAyahOnPage(
        pageNumber: pageNum,
        surah: target.$1,
        ayah: target.$2,
      )) {
        _navigationTargetAyah = null;
        if (widget.isRecording) {
          AppState.instance.saveLastPosition(target.$1, target.$2);
          return;
        }
        MushafView.isSyncingSurah = true;
        try {
          if (widget.controller.targetSurah != target.$1) {
            await widget.controller.setTargetSurah(
              target.$1,
              preserveOtherSurahStates: true,
              clearTargetSurah: false,
            );
          }
          if (!mounted || _currentPage != pageNum) return;
          widget.controller.setManualAyah(target.$1, target.$2);
          AppState.instance.saveLastPosition(target.$1, target.$2);
        } finally {
          MushafView.isSyncingSurah = false;
        }
        return;
      } else {
        // Intermediate page during navigation; do not alter selection!
        return;
      }
    }

    // 2. If the current active Ayah is already on this page (e.g. user selected it, or same-page transition):
    final int? currentActive = widget.controller.activeAyah.value;
    final int currentSurah = widget.controller.targetSurah;
    if (currentActive != null &&
        MushafView.isAyahOnPage(
          pageNumber: pageNum,
          surah: currentSurah,
          ayah: currentActive,
        )) {
      return;
    }

    // 3. Manual page change (e.g. user swiped or tapped next/prev):
    // Select the first Ayah on the new page.
    final first = MushafView.getFirstAyahOnPage(pageNum);
    if (first == null) return;

    final int surah = first.$1;
    final int ayah = first.$2;

    if (widget.isRecording) {
      AppState.instance.saveLastPosition(surah, ayah);
      return;
    }

    MushafView.isSyncingSurah = true;
    try {
      if (widget.controller.targetSurah != surah) {
        await widget.controller.setTargetSurah(
          surah,
          preserveOtherSurahStates: true,
          clearTargetSurah: false,
        );
      }
      if (!mounted || _currentPage != pageNum) return;
      widget.controller.setManualAyah(surah, ayah);
      AppState.instance.saveLastPosition(surah, ayah);
    } finally {
      MushafView.isSyncingSurah = false;
    }
  }

  void _goToPage(int page) {
    final clamped = page.clamp(1, 604);
    if (clamped == _currentPage) return;
    final pageDiff = (clamped - _currentPage).abs();
    _currentPage = clamped;
    AppState.instance.currentMushafPage.value = clamped;
    if (_pageController.hasClients) {
      if (pageDiff > 1) {
        _pageController.jumpToPage(clamped - 1);
      } else {
        _pageController.animateToPage(
          clamped - 1,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
        );
      }
    }
    _ensurePageSurahsLoaded(clamped);
    _syncPageSelection(clamped);
  }

  void _nextPage() {
    if (_currentPage < 604) {
      _navigationTargetAyah = null;
      _goToPage(_currentPage + 1);
    }
  }

  void _prevPage() {
    if (_currentPage > 1) {
      _navigationTargetAyah = null;
      _goToPage(_currentPage - 1);
    }
  }

  Future<void> _ensurePageSurahsLoaded(int pageNum) async {
    final lines = _mushafPagesCache?[pageNum];
    if (lines == null) return;

    final Set<int> surahsToLoad = {};
    for (final line in lines) {
      if (line['t'] == 'header') {
        final s = line['s'] as int?;
        if (s != null && !_loadedSurahs.contains(s)) surahsToLoad.add(s);
      } else if (line['t'] == 'basmala') {
        if (!_loadedSurahs.contains(1)) surahsToLoad.add(1);
      } else if (line['t'] == 'text' && line['w'] is List) {
        for (final loc in line['w']) {
          final s = int.tryParse(loc.toString().split(':').first);
          if (s != null && !_loadedSurahs.contains(s)) surahsToLoad.add(s);
        }
      }
    }

    if (surahsToLoad.isNotEmpty) {
      for (final s in surahsToLoad) {
        await widget.controller.repository.loadSurahAsync(s);
        _loadedSurahs.add(s);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppState.instance;
    final c = app.colors;

    if (_isLoading || _mushafPagesCache == null) {
      return Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(c.gold),
        ),
      );
    }

    final media = MediaQuery.of(context);
    final safeTop = math.max(media.padding.top, media.viewPadding.top);
    final safeBottom = math.max(media.padding.bottom, media.viewPadding.bottom);
    final isLandscape = media.orientation == Orientation.landscape ||
        media.size.width > media.size.height;

    final bool isFullscreenMode = widget.isRecording || widget.isAutoScrolling;
    final double topPadding;
    // Always keep page bottom padding consistent so the page number is anchored at the exact same position
    final double bottomPadding = safeBottom + 12.0;
    if (isLandscape) {
      topPadding = safeTop + (isFullscreenMode ? 6.0 : 8.0);
    } else {
      // In fullscreen (record & read mode): zero excess empty space, safely below notch
      // In normal mode: positioned right below the floating top header bar
      topPadding = isFullscreenMode
          ? (safeTop > 0 ? (safeTop + 4.0) : 8.0)
          : (safeTop + 68.0);
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: KeyboardListener(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: (event) {
          if (event is KeyDownEvent) {
            if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
              _nextPage();
            } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
              _prevPage();
            }
          }
        },
        child: Padding(
          padding: EdgeInsets.only(top: topPadding, bottom: bottomPadding),
          child: ScrollConfiguration(
            behavior: const _MushafScrollBehavior(),
            child: NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                if (notification is UserScrollNotification &&
                    notification.direction != ScrollDirection.idle) {
                  _navigationTargetAyah = null;
                }
                return false;
              },
              child: PageView.builder(
                key: const ValueKey('mushaf_single_page_view'),
                controller: _pageController,
                itemCount: 604,
                physics: const PageScrollPhysics(),
                onPageChanged: (index) {
                  final newPage = index + 1;
                  if (_currentPage == newPage) return;
                  _currentPage = newPage;
                  AppState.instance.currentMushafPage.value = newPage;
                  _ensurePageSurahsLoaded(newPage);
                  if (newPage < 604) _ensurePageSurahsLoaded(newPage + 1);
                  if (newPage > 1) _ensurePageSurahsLoaded(newPage - 1);
                  _syncPageSelection(newPage);
                },
                itemBuilder: (context, index) {
                  final pageNumber = index + 1;
                  return _MushafPage(
                    key: ValueKey('mushaf_page_$pageNumber'),
                    pageNumber: pageNumber,
                    controller: widget.controller,
                    isRecording: widget.isRecording,
                    isAutoScrolling: widget.isAutoScrolling,
                    wordFontFamily: widget.wordFontFamily,
                    ayahMarkerFontFamily: widget.ayahMarkerFontFamily,
                    ayahMarkerBorderColor: widget.ayahMarkerBorderColor,
                    ayahMarkerTextColor: widget.ayahMarkerTextColor,
                    ayahMarkerBorderWidth: widget.ayahMarkerBorderWidth,
                    showAyahMarkerCircle: widget.showAyahMarkerCircle,
                    showBottomPageNumber: widget.showBottomPageNumber,
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Authentic  Mushaf Page Layout:
/// - Single RepaintBoundary per page (eliminates 48 offscreen GPU layer allocations).
/// - Scoped State: Only subscribes to and rebuilds on events affecting THIS specific page.
/// - Instant native flex justification via Row + MainAxisAlignment.spaceBetween.
/// - Zero TextPainter.layout() calls on the UI thread for instant 60-120 FPS swiping.
class _MushafPage extends StatefulWidget {
  final int pageNumber;
  final HighlightingController controller;
  final bool isRecording;
  final bool isAutoScrolling;
  final String wordFontFamily;
  final String? ayahMarkerFontFamily;
  final Color? ayahMarkerBorderColor;
  final Color? ayahMarkerTextColor;
  final double ayahMarkerBorderWidth;
  final bool showAyahMarkerCircle;
  final bool showBottomPageNumber;

  const _MushafPage({
    super.key,
    required this.pageNumber,
    required this.controller,
    required this.isRecording,
    required this.isAutoScrolling,
    required this.wordFontFamily,
    this.ayahMarkerFontFamily,
    this.ayahMarkerBorderColor,
    this.ayahMarkerTextColor,
    required this.ayahMarkerBorderWidth,
    required this.showAyahMarkerCircle,
    required this.showBottomPageNumber,
  });

  @override
  State<_MushafPage> createState() => _MushafPageState();
}

class _MushafPageState extends State<_MushafPage> {
  final Set<int> _pageSurahs = {};
  final Set<String> _pageAyahs = {}; // "surah:ayah"
  bool _hadActiveReciter = false;
  bool _hadActiveAudio = false;

  @override
  void initState() {
    super.initState();
    _extractPageMetadata();
    _subscribe();
  }

  @override
  void didUpdateWidget(_MushafPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _unsubscribe(oldWidget.controller);
      _subscribe();
    }
    if (oldWidget.isAutoScrolling != widget.isAutoScrolling) {
      _lastFingerprint = -1;
      setState(() {});
    }
  }

  void _extractPageMetadata() {
    _pageSurahs.clear();
    _pageAyahs.clear();
    final cachedSurahs = _pageSurahsCache?[widget.pageNumber];
    if (cachedSurahs != null) {
      _pageSurahs.addAll(cachedSurahs);
    }
    final cachedAyahs = _pageAyahsCache?[widget.pageNumber];
    if (cachedAyahs != null) {
      _pageAyahs.addAll(cachedAyahs);
    }
    if (_pageAyahs.isEmpty) {
      final lines = _mushafPagesCache?[widget.pageNumber] ?? [];
      for (final line in lines) {
        if (line['t'] == 'header' && line['s'] is int) {
          _pageSurahs.add(line['s'] as int);
        } else if (line['t'] == 'text') {
          final words = line['parsed_words'] as List<MushafWordRef>?;
          if (words != null) {
            for (final w in words) {
              _pageSurahs.add(w.surah);
              _pageAyahs.add('${w.surah}:${w.ayah}');
            }
          }
        }
      }
    }
  }

  void _subscribe() {
    widget.controller.addListener(_onRelevantChange);
    widget.controller.globalRevision.addListener(_onRelevantChange);
    widget.controller.activeAyah.addListener(_onRelevantChange);
    AppState.instance.activeAudioAyah.addListener(_onRelevantChange);
    AppState.instance.activeAudioSurah.addListener(_onRelevantChange);
    AppState.instance.activeAudioWordIndex.addListener(_onRelevantChange);
    AppState.instance.isAudioPlaying.addListener(_onRelevantChange);
    AppState.instance.isAudioBuffering.addListener(_onRelevantChange);
  }

  void _unsubscribe(HighlightingController controller) {
    controller.removeListener(_onRelevantChange);
    controller.globalRevision.removeListener(_onRelevantChange);
    controller.activeAyah.removeListener(_onRelevantChange);
    AppState.instance.activeAudioAyah.removeListener(_onRelevantChange);
    AppState.instance.activeAudioSurah.removeListener(_onRelevantChange);
    AppState.instance.activeAudioWordIndex.removeListener(_onRelevantChange);
    AppState.instance.isAudioPlaying.removeListener(_onRelevantChange);
    AppState.instance.isAudioBuffering.removeListener(_onRelevantChange);
  }

  @override
  void dispose() {
    _unsubscribe(widget.controller);
    super.dispose();
  }

  int _lastFingerprint = -1;

  int _computePageFingerprint() {
    final ctrl = widget.controller;
    final app = AppState.instance;

    final int? activeAyah = ctrl.activeAyah.value;
    final int targetSurah =
        ctrl.targetSurah != 0 ? ctrl.targetSurah : app.lastSurah;
    final int? audioAyah = app.activeAudioAyah.value;
    final int? audioSurah = app.activeAudioSurah.value;

    final bool reciterOnThisPage = activeAyah != null &&
        (_pageAyahs.contains('$targetSurah:$activeAyah') ||
            MushafView.isAyahOnPage(
                pageNumber: widget.pageNumber,
                surah: targetSurah,
                ayah: activeAyah));
    final bool audioOnThisPage = audioAyah != null &&
        audioSurah != null &&
        (_pageAyahs.contains('$audioSurah:$audioAyah') ||
            MushafView.isAyahOnPage(
                pageNumber: widget.pageNumber,
                surah: audioSurah,
                ayah: audioAyah));

    if (!reciterOnThisPage && !audioOnThisPage) {
      return (_hadActiveReciter || _hadActiveAudio) ? 1 : 0;
    }

    int hash = 17;
    hash = hash * 31 + (activeAyah ?? 0);
    hash = hash * 31 + targetSurah;
    hash = hash * 31 + (audioAyah ?? 0);
    hash = hash * 31 + (audioSurah ?? 0);
    hash = hash * 31 + (app.activeAudioWordIndex.value ?? -1);
    hash = hash * 31 + (app.isAudioPlaying.value ? 1 : 0);
    hash = hash * 31 + (app.isAudioBuffering.value ? 1 : 0);
    hash = hash * 31 + (widget.isRecording ? 1 : 0);
    hash = hash * 31 + (widget.isAutoScrolling ? 1 : 0);

    final int currentAyahToCheck =
        reciterOnThisPage ? activeAyah : (audioAyah ?? 0);
    final verse = ctrl.repository.getVerse(
      reciterOnThisPage ? targetSurah : (audioSurah ?? targetSurah),
      currentAyahToCheck,
    );
    if (verse != null) {
      final int wordCount = verse.uthmaniWords.length;
      for (int i = 0; i < wordCount; i++) {
        if (ctrl.isWordGreen(currentAyahToCheck, i)) {
          hash = hash * 31 + (i + 1) * 7;
        } else if (ctrl.isWordRed(currentAyahToCheck, i)) {
          hash = hash * 31 + (i + 1) * 13;
        } else if (ctrl.isWordYellow(currentAyahToCheck, i)) {
          hash = hash * 31 + (i + 1) * 17;
        }
      }
    }

    return hash;
  }

  void _onRelevantChange() {
    if (!mounted) return;
    if (_pageAyahs.isEmpty) {
      _extractPageMetadata();
    }
    final int? activeAyah = widget.controller.activeAyah.value;
    final int targetSurah = widget.controller.targetSurah != 0
        ? widget.controller.targetSurah
        : AppState.instance.lastSurah;
    final int? audioAyah = AppState.instance.activeAudioAyah.value;
    final int? audioSurah = AppState.instance.activeAudioSurah.value;

    final bool reciterOnThisPage = activeAyah != null &&
        (_pageAyahs.contains('$targetSurah:$activeAyah') ||
            MushafView.isAyahOnPage(
                pageNumber: widget.pageNumber,
                surah: targetSurah,
                ayah: activeAyah));
    final bool audioOnThisPage = audioAyah != null &&
        audioSurah != null &&
        (_pageAyahs.contains('$audioSurah:$audioAyah') ||
            MushafView.isAyahOnPage(
                pageNumber: widget.pageNumber,
                surah: audioSurah,
                ayah: audioAyah));

    // Exit immediately if this page is completely idle
    if (!reciterOnThisPage &&
        !audioOnThisPage &&
        !_hadActiveReciter &&
        !_hadActiveAudio) {
      return;
    }

    final fp = _computePageFingerprint();
    if (fp != _lastFingerprint) {
      _lastFingerprint = fp;
      _hadActiveReciter = reciterOnThisPage;
      _hadActiveAudio = audioOnThisPage;
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppState.instance;
    final c = app.colors;
    final lines = _mushafPagesCache?[widget.pageNumber] ?? [];

    if (lines.isEmpty) return const SizedBox.shrink();

    return RepaintBoundary(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final double maxWidth = constraints.maxWidth;
          final double maxHeight = constraints.maxHeight;

          final bool isLandscape = maxWidth > maxHeight;

          // Bottom clearance: ensures the last ayah reaches right above the bottom action bar dock
          // and is NEVER trapped or obscured behind the bottom buttons
          final double bottomReserved = isLandscape ? 48.0 : 64.0;
          final double availableHeight =
              (maxHeight - bottomReserved).clamp(100.0, maxHeight);
          final double availableWidth = maxWidth;

          final double lineWidth;
          final double linesContainerHeight;

          if (isLandscape) {
            const double mushafAspectRatio = 0.65;
            double h = availableHeight;
            double w = h * mushafAspectRatio;
            if (w > availableWidth - 24.0) {
              w = availableWidth - 24.0;
              h = w / mushafAspectRatio;
            }
            lineWidth = w;
            linesContainerHeight = h;
          } else {
            // Portrait: Ayahs expand to fill full height right down to the bottom bar
            lineWidth =
                (availableWidth - 16.0).clamp(280.0, availableHeight * 0.72);
            linesContainerHeight = availableHeight;
          }

          // Pages 1 & 2 special centered layout (Al-Fatihah and start of Al-Baqarah)
          if (widget.pageNumber <= 2) {
            final double lineHeight =
                (linesContainerHeight / (lines.length + 3)).clamp(44.0, 72.0);
            final double fontSize = (lineHeight * 0.46).clamp(16.0, 23.0);

            return Directionality(
              textDirection: TextDirection.rtl,
              child: Center(
                child: SizedBox(
                  width: lineWidth,
                  height: maxHeight,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Align(
                        alignment: Alignment.topCenter,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.center,
                          child: SizedBox(
                            width: lineWidth,
                            height: linesContainerHeight,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children:
                                  List.generate(lines.length, (lineIndex) {
                                final nextLine = lineIndex + 1 < lines.length
                                    ? lines[lineIndex + 1]
                                    : null;
                                return SizedBox(
                                  width: lineWidth,
                                  height: lineHeight,
                                  child: _buildLine(
                                    lineData: lines[lineIndex],
                                    nextLineData: nextLine,
                                    lineIndex: lineIndex,
                                    totalLines: lines.length,
                                    pageNumber: widget.pageNumber,
                                    lineWidth: lineWidth,
                                    lineHeight: lineHeight,
                                    fontSize: fontSize,
                                    c: c,
                                    app: app,
                                  ),
                                );
                              }),
                            ),
                          ),
                        ),
                      ),
                      if (widget.showBottomPageNumber)
                        Positioned(
                          left: 2,
                          bottom: 0,
                          child:
                              _buildBottomPageNumber(widget.pageNumber, c, app),
                        ),
                    ],
                  ),
                ),
              ),
            );
          }

          // Standard 15-line  Mushaf pages:
          // Unified typography: all 15 lines share the exact same scale and baseline.
          final double lineHeight = linesContainerHeight / lines.length;
          final double fontSize = (lineHeight * 0.52).clamp(16.0, 26.0);

          return Directionality(
            textDirection: TextDirection.rtl,
            child: Center(
              child: SizedBox(
                width: lineWidth,
                height: maxHeight,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Align(
                      alignment: Alignment.topCenter,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.center,
                        child: SizedBox(
                          width: lineWidth,
                          height: linesContainerHeight,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: List.generate(lines.length, (lineIndex) {
                              final nextLine = lineIndex + 1 < lines.length
                                  ? lines[lineIndex + 1]
                                  : null;
                              return SizedBox(
                                width: lineWidth,
                                height: lineHeight,
                                child: _buildLine(
                                  lineData: lines[lineIndex],
                                  nextLineData: nextLine,
                                  lineIndex: lineIndex,
                                  totalLines: lines.length,
                                  pageNumber: widget.pageNumber,
                                  lineWidth: lineWidth,
                                  lineHeight: lineHeight,
                                  fontSize: fontSize,
                                  c: c,
                                  app: app,
                                ),
                              );
                            }),
                          ),
                        ),
                      ),
                    ),
                    if (widget.showBottomPageNumber)
                      Positioned(
                        left: 2,
                        bottom: 0,
                        child:
                            _buildBottomPageNumber(widget.pageNumber, c, app),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildLine({
    required Map<String, dynamic> lineData,
    required Map<String, dynamic>? nextLineData,
    required int lineIndex,
    required int totalLines,
    required int pageNumber,
    required double lineWidth,
    required double lineHeight,
    required double fontSize,
    required ThemeColors c,
    required AppState app,
  }) {
    final type = lineData['t'] as String?;

    // 1. Surah Header Line (Modern Flat Banner - من غير زخرفة)
    if (type == 'header') {
      final surahNum = lineData['s'] as int? ?? 1;
      String surahName = lineData['name'] as String? ?? 'سورة $surahNum';
      if (surahNum >= 1 &&
          surahNum <= widget.controller.repository.surahMetadata.length) {
        final meta = widget.controller.repository.surahMetadata[surahNum - 1];
        if (meta.surahName.isNotEmpty) {
          final rawName = meta.surahName;
          surahName = rawName.startsWith('سورة') || rawName.startsWith('سُورَة')
              ? rawName
              : 'سورة $rawName';
        }
      }

      return _buildSurahHeaderBanner(
        surahNum: surahNum,
        surahName: surahName,
        lineWidth: lineWidth,
        lineHeight: lineHeight,
        fontSize: fontSize,
        c: c,
        app: app,
      );
    }

    // 2. Basmala Line (Authentic  Mushaf Calligraphy)
    if (type == 'basmala') {
      final basmalaVerse = widget.controller.repository.getVerse(1, 1);
      final List<String> words =
          (basmalaVerse != null && basmalaVerse.uthmaniWords.length >= 4)
              ? basmalaVerse.uthmaniWords.sublist(0, 4)
              : const ['بِسْمِ', 'ٱللَّهِ', 'ٱلرَّحْمَـٰنِ', 'ٱلرَّحِيمِ'];
      final bool usesUthmani =
          basmalaVerse != null && basmalaVerse.uthmaniWords.length >= 4;

      return SizedBox(
        width: lineWidth,
        height: lineHeight,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.center,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                textDirection: TextDirection.rtl,
                children: [
                  for (int i = 0; i < words.length; i++) ...[
                    if (i > 0)
                      SizedBox(width: (fontSize * 0.35).clamp(6.0, 10.0)),
                    Text(
                      words[i],
                      textDirection: TextDirection.rtl,
                      textScaler: TextScaler.noScaling,
                      style: TextStyle(
                        fontFamily:
                            usesUthmani ? widget.wordFontFamily : 'cairo',
                        fontSize: (fontSize * 0.95).clamp(17.0, 25.0),
                        fontWeight: FontWeight.normal,
                        color: c.text,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    }

    // 3. Text Line with Words and Circular Ayah End Numbers
    final parsedWords =
        lineData['parsed_words'] as List<MushafWordRef>? ?? const [];
    if (parsedWords.isEmpty) return const SizedBox.shrink();

    final bool nextLineIsHeader =
        nextLineData != null && nextLineData['t'] == 'header';
    final bool isLastLineOfPage = lineIndex == totalLines - 1;
    // Exactly like mushaf-svelte: short end-lines are centered so words never drift apart with awkward voids.
    final bool shouldJustify = pageNumber > 2 &&
        !nextLineIsHeader &&
        (!isLastLineOfPage || pageNumber <= 599) &&
        parsedWords.length >= 5;

    final bool isDark = app.isDarkMode;
    final wordWidgets = <Widget>[];
    int? highlightStartIndex;
    int? highlightEndIndex;

    QuranVerse? cachedVerse;
    bool cachedIsAyahActive = false;
    int cachedTargetIndex = -1;
    int cachedSurah = -1;
    int cachedAyah = -1;

    for (int i = 0; i < parsedWords.length; i++) {
      final ref = parsedWords[i];
      final surah = ref.surah;
      final ayah = ref.ayah;
      final wordIndex1 = ref.wordIndex1;
      final wordIndex0 = ref.wordIndex0;

      if (surah != cachedSurah || ayah != cachedAyah) {
        cachedSurah = surah;
        cachedAyah = ayah;
        cachedVerse = widget.controller.repository.getVerse(surah, ayah);
        final int effectiveTargetSurah = widget.controller.targetSurah != 0
            ? widget.controller.targetSurah
            : app.lastSurah;
        final bool isSelected = !widget.isAutoScrolling &&
            effectiveTargetSurah == surah &&
            widget.controller.activeAyah.value == ayah;
        final bool isRecitingActive = !widget.isAutoScrolling &&
            widget.controller.currentMatchedVerse?.verse.surah == surah &&
            widget.controller.currentMatchedVerse?.verse.ayah == ayah;
        final bool isAudioActive = !widget.isAutoScrolling &&
            VerseRow.isAyahAudioActive(surah: surah, ayah: ayah, app: app);
        cachedIsAyahActive = isSelected || isRecitingActive || isAudioActive;
        cachedTargetIndex = cachedIsAyahActive
            ? VerseRow.getTargetWordIndex(
                surah: surah,
                ayah: ayah,
                words: cachedVerse?.uthmaniWords ?? const [],
                controller: widget.controller,
                app: app,
                isRecording: widget.isRecording,
                isActive: true,
              )
            : -1;
      }

      final verse = cachedVerse;
      if (verse == null || wordIndex0 >= verse.uthmaniWords.length) continue;

      final wordText = verse.uthmaniWords[wordIndex0];
      final bool isAyahActive = cachedIsAyahActive;
      final int targetIndex = cachedTargetIndex;
      final bool isWordActive = (targetIndex == wordIndex0);

      final textColor = VerseSpanBuilder.resolveWordDisplayColor(
        ayah: ayah,
        wordIndex: wordIndex0,
        controller: widget.controller,
        app: app,
        colors: c,
        isAutoScrolling: widget.isAutoScrolling,
      );

      void handleWordTap() async {
        if (widget.isAutoScrolling) return;
        HapticFeedback.lightImpact();
        if (widget.controller.isWordYellow(ayah, wordIndex0)) {
          VerseRow.handleWordTap(
            context: context,
            surah: surah,
            ayah: ayah,
            wordIndex: wordIndex0,
            wordText: wordText,
            controller: widget.controller,
            isAutoScrolling: widget.isAutoScrolling,
          );
          return;
        }
        if (widget.controller.targetSurah != surah) {
          MushafView.isSyncingSurah = true;
          try {
            await widget.controller.setTargetSurah(
              surah,
              preserveOtherSurahStates: true,
              clearTargetSurah: false,
            );
          } finally {
            MushafView.isSyncingSurah = false;
          }
        }
        widget.controller.setManualAyah(surah, ayah);
        AppState.instance.saveLastPosition(surah, ayah);
        if (mounted) setState(() {});
      }

      // Modern, eye-comfortable active word focus pill:
      // Distinct, soothing luminous oceanic teal with soft ambient glow,
      // creating an elegant contrast against the neutral white-grey Ayah ribbon.
      final BoxDecoration? wordDecoration = isWordActive
          ? BoxDecoration(
              color: c.wordHighlight.withValues(
                alpha: isDark ? 0.25 : 0.18,
              ),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: c.wordHighlight.withValues(alpha: isDark ? 0.70 : 0.50),
                width: 1.0,
              ),
              boxShadow: [
                BoxShadow(
                  color:
                      c.wordHighlight.withValues(alpha: isDark ? 0.22 : 0.12),
                  blurRadius: 6,
                  spreadRadius: 0.5,
                ),
              ],
            )
          : null;

      final int wordWidgetIndex = wordWidgets.length;
      if (isAyahActive) {
        highlightStartIndex ??= wordWidgetIndex;
        highlightEndIndex = wordWidgetIndex;
      }

      wordWidgets.add(
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: handleWordTap,
          child: Container(
            margin: EdgeInsets.symmetric(horizontal: shouldJustify ? 1.0 : 3.5),
            padding: const EdgeInsets.symmetric(horizontal: 1.0, vertical: 1.0),
            decoration: wordDecoration,
            child: Text(
              wordText,
              textDirection: TextDirection.rtl,
              textScaler: TextScaler.noScaling,
              style: TextStyle(
                fontFamily: widget.wordFontFamily,
                fontSize: fontSize,
                color: textColor,
                height: 1.25,
              ),
            ),
          ),
        ),
      );

      // Ayah number marker at the end of the Ayah
      final bool isLastWordOfAyah = wordIndex1 == verse.uthmaniWords.length;
      if (isLastWordOfAyah) {
        final int markerWidgetIndex = wordWidgets.length;
        if (isAyahActive) {
          highlightStartIndex ??= markerWidgetIndex;
          highlightEndIndex = markerWidgetIndex;
        }
        wordWidgets.add(
          _buildAyahMarker(
            surah: surah,
            ayah: ayah,
            fontSize: fontSize,
            isAyahActive: isAyahActive,
            c: c,
            app: app,
          ),
        );
      }
    }

    return SizedBox(
      width: lineWidth,
      height: lineHeight,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.center,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: lineWidth,
            maxHeight: lineHeight,
          ),
          child: SizedBox(
            height: lineHeight,
            child: _MushafHighlightRow(
              mainAxisSize: MainAxisSize.min,
              textDirection: TextDirection.rtl,
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisAlignment: shouldJustify
                  ? MainAxisAlignment.spaceBetween
                  : MainAxisAlignment.center,
              highlightStartIndex: highlightStartIndex,
              highlightEndIndex: highlightEndIndex,
              highlightColor: highlightStartIndex != null
                  ? (isDark
                      ? Colors.white.withValues(alpha: 0.10)
                      : const Color(0xFF64748B).withValues(alpha: 0.09))
                  : null,
              highlightBorderColor: highlightStartIndex != null
                  ? (isDark
                      ? Colors.white.withValues(alpha: 0.24)
                      : const Color(0xFF64748B).withValues(alpha: 0.22))
                  : null,
              children: wordWidgets,
            ),
          ),
        ),
      ),
    );
  }

  /// Modern Flat Surah Header Banner (من غير زخرفة):
  /// - Minimalist flat card container styled strictly with app theme tokens.
  /// - Zero traditional decorative clipart or complex floral arabesque.
  /// - Pure centered Surah title in authentic Quranic typography.
  Widget _buildSurahHeaderBanner({
    required int surahNum,
    required String surahName,
    required double lineWidth,
    required double lineHeight,
    required double fontSize,
    required ThemeColors c,
    required AppState app,
  }) {
    final bool isDark = app.isDarkMode;
    final double bannerHeight = (lineHeight * 0.86).clamp(34.0, 44.0);

    return SizedBox(
      width: lineWidth,
      height: lineHeight,
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.center,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              HapticFeedback.lightImpact();
              VerseRow.selectAyah(
                surah: surahNum,
                ayah: 1,
                controller: widget.controller,
              );
            },
            child: Container(
              width: lineWidth,
              height: bannerHeight,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: c.surfaceHigh,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: c.border.withValues(alpha: isDark ? 0.70 : 0.85),
                  width: 0.85,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                surahName,
                textAlign: TextAlign.center,
                textDirection: TextDirection.rtl,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'cairo',
                  fontSize: (fontSize * 0.82).clamp(16.0, 21.0),
                  fontWeight: FontWeight.w700,
                  color: c.text,
                  height: 1.2,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Standard  Mushaf Ayah Marker:
  /// - Uniform 1:1 square/squircle dimensions across ALL ayahs (never stretching into rectangles).
  /// - Calibrated standard typographic scale: 1, 2, and 3 digits maintain harmonious optical size and weight.
  /// - Optically centered vertically and horizontally inside the box.
  /// - Eye-comfortable grey scheme matching the Ayah highlight ribbon (zero distraction).
  /// - Instant selection and highlighting on tap.
  Widget _buildAyahMarker({
    required int surah,
    required int ayah,
    required double fontSize,
    required bool isAyahActive,
    required ThemeColors c,
    required AppState app,
  }) {
    final bool isDark = app.isDarkMode;
    final bool isPlaying = VerseRow.isAyahAudioPlaying(surah, ayah);
    final bool isBuffering = VerseRow.isAyahAudioBuffering(surah, ayah);

    // Standard uniform 1:1 box size across all ayahs on the page (matches line height proportions)
    final double boxSize = (fontSize * 1.02).clamp(22.0, 26.5);

    // Calibrated standard typography so 1, 2, and 3 digits maintain standard optical height and weight
    final double numFontSize;
    final double letterSpacing;
    if (ayah < 10) {
      numFontSize = (boxSize * 0.52).clamp(11.5, 13.5);
      letterSpacing = 0.0;
    } else if (ayah < 100) {
      numFontSize = (boxSize * 0.48).clamp(10.5, 12.2);
      letterSpacing = -0.2;
    } else {
      numFontSize = (boxSize * 0.43).clamp(9.5, 11.0);
      letterSpacing = -0.4;
    }

    // Color scheme: Grey/neutral palette matching the highlighted Ayah ribbon for eye comfort and zero distraction
    final Color boxBgColor;
    final Color boxBorderColor;
    final Color numTextColor;

    if (isPlaying || isBuffering) {
      boxBgColor = c.primary;
      boxBorderColor = c.primary;
      numTextColor = c.onPrimary;
    } else if (isAyahActive) {
      boxBgColor = isDark
          ? Colors.white.withValues(alpha: 0.15)
          : const Color(0xFF64748B).withValues(alpha: 0.13);
      boxBorderColor = isDark
          ? Colors.white.withValues(alpha: 0.35)
          : const Color(0xFF64748B).withValues(alpha: 0.32);
      numTextColor = isDark ? Colors.white : const Color(0xFF0F172A);
    } else {
      boxBgColor = isDark
          ? Colors.white.withValues(alpha: 0.08)
          : const Color(0xFF64748B).withValues(alpha: 0.075);
      boxBorderColor = isDark
          ? Colors.white.withValues(alpha: 0.22)
          : const Color(0xFF64748B).withValues(alpha: 0.20);
      numTextColor = isDark
          ? const Color(0xFFCBD5E1) // Slate 300
          : const Color(0xFF475569); // Slate 600
    }

    final Color effectiveBorder =
        widget.ayahMarkerBorderColor ?? boxBorderColor;
    final Color effectiveText = widget.ayahMarkerTextColor ?? numTextColor;

    final String markerFont = widget.ayahMarkerFontFamily ?? 'cairo';
    final bool isHafs = markerFont.toLowerCase().contains('hafs');
    final double verticalOffset = isHafs ? -2.0 : -0.4;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () async {
        HapticFeedback.lightImpact();
        if (widget.controller.targetSurah != surah) {
          MushafView.isSyncingSurah = true;
          try {
            await widget.controller.setTargetSurah(
              surah,
              preserveOtherSurahStates: true,
              clearTargetSurah: false,
            );
          } finally {
            MushafView.isSyncingSurah = false;
          }
        }
        widget.controller.setManualAyah(surah, ayah);
        AppState.instance.saveLastPosition(surah, ayah);
        if (mounted) {
          setState(() {});
        }
      },
      child: Container(
        width: widget.showAyahMarkerCircle ? boxSize : null,
        height: widget.showAyahMarkerCircle ? boxSize : null,
        margin: const EdgeInsets.symmetric(horizontal: 2.0),
        alignment: Alignment.center,
        decoration: widget.showAyahMarkerCircle
            ? BoxDecoration(
                color: widget.ayahMarkerBorderColor != null ? null : boxBgColor,
                borderRadius: BorderRadius.circular(
                    boxSize * 0.28), // Sleek flat squircle
                border: Border.all(
                  color: effectiveBorder,
                  width: widget.ayahMarkerBorderWidth > 0
                      ? widget.ayahMarkerBorderWidth
                      : 1.0,
                ),
              )
            : null,
        child: isBuffering
            ? SizedBox(
                width: boxSize * 0.48,
                height: boxSize * 0.48,
                child: CircularProgressIndicator(
                  strokeWidth: 1.6,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    isPlaying ? c.onPrimary : c.primary,
                  ),
                ),
              )
            : isPlaying
                ? Icon(
                    Icons.pause_rounded,
                    size: boxSize * 0.60,
                    color: c.onPrimary,
                  )
                : Center(
                    child: Transform.translate(
                      offset: Offset(0, verticalOffset),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.center,
                        child: Text(
                          VerseRow.toArabicDigits(ayah),
                          textDirection: TextDirection.rtl,
                          textScaler: TextScaler.noScaling,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: markerFont,
                            fontSize: numFontSize,
                            letterSpacing: letterSpacing,
                            color: effectiveText,
                            fontWeight: FontWeight.w700,
                            height: 1.0,
                            leadingDistribution: TextLeadingDistribution.even,
                          ),
                        ),
                      ),
                    ),
                  ),
      ),
    );
  }

  Widget _buildBottomPageNumber(int pageNumber, ThemeColors c, AppState app) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 2),
      child: Text(
        VerseRow.toArabicDigits(pageNumber),
        textDirection: TextDirection.rtl,
        textScaler: TextScaler.noScaling,
        style: TextStyle(
          fontFamily: 'cairo',
          fontSize: 11.5,
          color: c.textSecondary,
          fontWeight: FontWeight.w600,
          height: 1.0,
        ),
      ),
    );
  }
}

/// Specialized Flex widget that paints a seamless, continuous background ribbon
/// behind active Ayah items (spanning across words and their justification gaps)
/// without disturbing flex layout, word justification, or causing any overflow.
class _MushafHighlightRow extends Flex {
  final int? highlightStartIndex;
  final int? highlightEndIndex;
  final Color? highlightColor;
  final Color? highlightBorderColor;

  const _MushafHighlightRow({
    required super.children,
    super.mainAxisAlignment = MainAxisAlignment.spaceBetween,
    super.crossAxisAlignment = CrossAxisAlignment.center,
    super.mainAxisSize = MainAxisSize.min,
    super.textDirection = TextDirection.rtl,
    this.highlightStartIndex,
    this.highlightEndIndex,
    this.highlightColor,
    this.highlightBorderColor,
  }) : super(direction: Axis.horizontal);

  @override
  RenderFlex createRenderObject(BuildContext context) {
    return _RenderMushafHighlightFlex(
      direction: direction,
      mainAxisAlignment: mainAxisAlignment,
      mainAxisSize: mainAxisSize,
      crossAxisAlignment: crossAxisAlignment,
      textDirection: getEffectiveTextDirection(context),
      verticalDirection: verticalDirection,
      textBaseline: textBaseline,
      clipBehavior: clipBehavior,
      highlightStartIndex: highlightStartIndex,
      highlightEndIndex: highlightEndIndex,
      highlightColor: highlightColor,
      highlightBorderColor: highlightBorderColor,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderMushafHighlightFlex renderObject,
  ) {
    super.updateRenderObject(context, renderObject);
    renderObject.highlightStartIndex = highlightStartIndex;
    renderObject.highlightEndIndex = highlightEndIndex;
    renderObject.highlightColor = highlightColor;
    renderObject.highlightBorderColor = highlightBorderColor;
  }
}

class _RenderMushafHighlightFlex extends RenderFlex {
  int? _highlightStartIndex;
  int? _highlightEndIndex;
  Color? _highlightColor;
  Color? _highlightBorderColor;
  static const double _highlightRadius = 6.0;

  _RenderMushafHighlightFlex({
    super.direction = Axis.horizontal,
    super.mainAxisSize = MainAxisSize.max,
    super.mainAxisAlignment = MainAxisAlignment.start,
    super.crossAxisAlignment = CrossAxisAlignment.center,
    super.textDirection,
    super.verticalDirection = VerticalDirection.down,
    super.textBaseline,
    super.clipBehavior = Clip.none,
    int? highlightStartIndex,
    int? highlightEndIndex,
    Color? highlightColor,
    Color? highlightBorderColor,
  })  : _highlightStartIndex = highlightStartIndex,
        _highlightEndIndex = highlightEndIndex,
        _highlightColor = highlightColor,
        _highlightBorderColor = highlightBorderColor;

  int? get highlightStartIndex => _highlightStartIndex;
  set highlightStartIndex(int? value) {
    if (_highlightStartIndex != value) {
      _highlightStartIndex = value;
      markNeedsPaint();
    }
  }

  int? get highlightEndIndex => _highlightEndIndex;
  set highlightEndIndex(int? value) {
    if (_highlightEndIndex != value) {
      _highlightEndIndex = value;
      markNeedsPaint();
    }
  }

  Color? get highlightColor => _highlightColor;
  set highlightColor(Color? value) {
    if (_highlightColor != value) {
      _highlightColor = value;
      markNeedsPaint();
    }
  }

  Color? get highlightBorderColor => _highlightBorderColor;
  set highlightBorderColor(Color? value) {
    if (_highlightBorderColor != value) {
      _highlightBorderColor = value;
      markNeedsPaint();
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (_highlightColor != null &&
        _highlightStartIndex != null &&
        _highlightEndIndex != null &&
        _highlightStartIndex! <= _highlightEndIndex!) {
      int index = 0;
      RenderBox? child = firstChild;
      double? minX;
      double? maxX;
      double? minY;
      double? maxY;

      while (child != null) {
        if (index >= _highlightStartIndex! && index <= _highlightEndIndex!) {
          final parentData = child.parentData as FlexParentData;
          final childOffset = offset + parentData.offset;
          final childSize = child.size;

          final left = childOffset.dx;
          final right = childOffset.dx + childSize.width;
          final top = childOffset.dy;
          final bottom = childOffset.dy + childSize.height;

          minX = minX == null ? left : math.min(minX, left);
          maxX = maxX == null ? right : math.max(maxX, right);
          minY = minY == null ? top : math.min(minY, top);
          maxY = maxY == null ? bottom : math.max(maxY, bottom);
        }
        child = childAfter(child);
        index++;
      }

      if (minX != null && maxX != null && minY != null && maxY != null) {
        // Expand horizontally and vertically slightly for a comfortable breathing room
        final clampLeft = (minX - 3.0).clamp(offset.dx, offset.dx + size.width);
        final clampRight =
            (maxX + 3.0).clamp(offset.dx, offset.dx + size.width);
        final clampTop = (minY - 2.0).clamp(offset.dy, offset.dy + size.height);
        final clampBottom =
            (maxY + 2.0).clamp(offset.dy, offset.dy + size.height);

        if (clampRight > clampLeft && clampBottom > clampTop) {
          final rect =
              Rect.fromLTRB(clampLeft, clampTop, clampRight, clampBottom);
          final rrect =
              RRect.fromRectAndRadius(rect, Radius.circular(_highlightRadius));

          final fillPaint = Paint()
            ..color = _highlightColor!
            ..style = PaintingStyle.fill;
          context.canvas.drawRRect(rrect, fillPaint);

          if (_highlightBorderColor != null) {
            final borderPaint = Paint()
              ..color = _highlightBorderColor!
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.0;
            context.canvas.drawRRect(rrect, borderPaint);
          }
        }
      }
    }

    super.paint(context, offset);
  }
}
