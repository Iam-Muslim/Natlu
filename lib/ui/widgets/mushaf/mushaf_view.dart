import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:recite_quran/recite_quran.dart';

import '../../../services/quran_audio_service.dart';
import '../../../state/app_state.dart';
import '../dialogs/error_detail_dialog.dart';
import '../helpers/verse_span_builder.dart';

/// Desktop & Mobile friendly scroll behavior allowing mouse drag on PageView
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

/// Optional Mushaf Layout View.
/// - Fills the entire screen cleanly without overflow.
/// - Never overlaps or hides behind the top toolbar.
/// - Displays Surah name & number ONLY at the start of each Surah (no fixed page headers, no juz numbers).
/// - Displays Ayah numbers inside a clean decorative circle at every verse end.
/// - Displays only ONE centered page number in Arabic numerals at the bottom.
/// - Supports mouse dragging, touch swipe, and keyboard arrow keys to shift pages.
class MushafView extends StatefulWidget {
  final HighlightingController controller;
  final bool isRecording;
  final bool isAutoScrolling;
  final VoidCallback? onToggleAutoScroll;

  const MushafView({
    super.key,
    required this.controller,
    required this.isRecording,
    this.isAutoScrolling = false,
    this.onToggleAutoScroll,
  });

  @override
  State<MushafView> createState() => _MushafViewState();
}

class _MushafViewState extends State<MushafView> {
  late PageController _pageController;
  int _currentPage = 1;
  bool _isLoading = true;
  final Set<int> _loadedSurahs = {};
  final FocusNode _focusNode = FocusNode();

  static const double basePageWidth = 794.0;
  static const double basePageHeight = 1123.0;
  static const double baseFontSize = 32.5;

  @override
  void initState() {
    super.initState();
    _currentPage = _findInitialPage();
    _pageController = PageController(initialPage: _currentPage - 1);

    widget.controller.activeAyah.addListener(_onActiveAyahChanged);
    widget.controller.globalRevision.addListener(_onStateChanged);
    AppState.instance.addListener(_onStateChanged);

    _initMushafData();
  }

  int _findInitialPage() {
    final surah = widget.controller.targetSurah;
    final ayah = widget.controller.activeAyah.value ?? 1;
    if (_ayahToPageCache != null) {
      final key = '$surah:$ayah';
      return _ayahToPageCache![key] ?? 1;
    }
    return 1;
  }

  Future<void> _initMushafData() async {
    if (_mushafPagesCache == null) {
      try {
        final jsonStr = await rootBundle.loadString('assets/data/mushaf_pages.json');
        final Map<String, dynamic> rawMap = json.decode(jsonStr);

        final Map<int, List<Map<String, dynamic>>> pages = {};
        final Map<String, int> ayahMap = {};

        rawMap.forEach((key, val) {
          final pageNum = int.tryParse(key);
          if (pageNum != null && val is List) {
            final List<Map<String, dynamic>> lines = [];
            for (final line in val) {
              if (line is Map) {
                final castedLine = Map<String, dynamic>.from(line);
                lines.add(castedLine);
                if (castedLine['t'] == 'text' && castedLine['w'] is List) {
                  for (final loc in castedLine['w']) {
                    final parts = loc.toString().split(':');
                    if (parts.length >= 2) {
                      final ayahKey = '${parts[0]}:${parts[1]}';
                      ayahMap.putIfAbsent(ayahKey, () => pageNum);
                    }
                  }
                }
              }
            }
            pages[pageNum] = lines;
          }
        });

        _mushafPagesCache = pages;
        _ayahToPageCache = ayahMap;
      } catch (e) {
        debugPrint('Error loading mushaf_pages.json: $e');
      }
    }

    if (mounted) {
      final initialPage = _findInitialPage();
      _currentPage = initialPage;
      final targetIndex = _currentPage - 1;
      if (_pageController.hasClients && (_pageController.page?.round() ?? 0) != targetIndex) {
        _pageController.jumpToPage(targetIndex);
      }
      _ensurePageSurahsLoaded(_currentPage);
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    widget.controller.activeAyah.removeListener(_onActiveAyahChanged);
    widget.controller.globalRevision.removeListener(_onStateChanged);
    AppState.instance.removeListener(_onStateChanged);
    _pageController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onStateChanged() {
    if (mounted) {
      if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
        SchedulerBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() {});
        });
      } else {
        setState(() {});
      }
    }
  }

  void _onActiveAyahChanged() {
    final active = widget.controller.activeAyah.value;
    if (active != null && _ayahToPageCache != null) {
      final surah = widget.controller.targetSurah;
      final targetPage = _ayahToPageCache!['$surah:$active'];
      if (targetPage != null && targetPage != _currentPage) {
        _goToPage(targetPage);
      }
    }
    if (mounted) {
      if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
        SchedulerBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() {});
        });
      } else {
        setState(() {});
      }
    }
  }

  void _goToPage(int page) {
    final clamped = page.clamp(1, 604);
    if (clamped == _currentPage) return;
    _currentPage = clamped;
    if (_pageController.hasClients) {
      _pageController.animateToPage(
        clamped - 1,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }
    _ensurePageSurahsLoaded(clamped);
    setState(() {});
  }

  void _nextPage() {
    if (_currentPage < 604) {
      _goToPage(_currentPage + 1);
    }
  }

  void _prevPage() {
    if (_currentPage > 1) {
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
      if (mounted) setState(() {});
    }
  }

  void _handleWordTap(int surah, int ayah, int wordIdx, String word) {
    if (widget.isAutoScrolling) return;

    if (widget.controller.isWordYellow(ayah, wordIdx)) {
      AppState.instance.markTajweedWordClicked();
      final errors = widget.controller.getWordErrors(ayah, wordIdx);
      if (errors != null && errors.isNotEmpty) {
        ErrorDetailDialog.show(
          context,
          word: word,
          errors: errors,
          surah: surah,
          ayah: ayah,
          wordIndex: wordIdx,
        );
        return;
      }
    }

    widget.controller.setManualAyah(surah, ayah);
    QuranAudioService.instance.playWord(
      surah: surah,
      ayah: ayah,
      wordIndex: wordIdx,
    );
  }

  static String _toArabicDigits(int number) {
    const digits = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
    return number.toString().split('').map((e) => digits[int.parse(e)]).join('');
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
    final safeTop = media.padding.top;
    final safeBottom = media.padding.bottom;
    final isLandscape = media.orientation == Orientation.landscape || media.size.width > media.size.height;

    // Responsive padding matching mushaf-svelte:
    // In landscape/desktop or recording mode, minimize padding so Mushaf uses 100% of viewport height.
    // In portrait reading mode, reserve just enough room for the top header and bottom bar.
    final double topPadding;
    final double bottomPadding;
    if (isLandscape) {
      topPadding = safeTop + (widget.isRecording ? 2.0 : 6.0);
      bottomPadding = safeBottom + 4.0;
    } else {
      topPadding = widget.isRecording ? (safeTop + 8.0) : (safeTop + 54.0);
      bottomPadding = widget.isRecording ? (safeBottom + 16.0) : (safeBottom + 70.0);
    }

    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: (event) {
        if (event is KeyDownEvent) {
          // In RTL Quran reading:
          // Left arrow advances forward, Right arrow goes backward
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
          child: PageView.builder(
            key: const ValueKey('mushaf_single_page_view'),
            controller: _pageController,
            itemCount: 604,
            reverse: false, // Standard page turn: drag left to advance to next page
            physics: const PageScrollPhysics(),
            onPageChanged: (index) {
              final newPage = index + 1;
              _currentPage = newPage;
              _ensurePageSurahsLoaded(newPage);
              if (newPage < 604) _ensurePageSurahsLoaded(newPage + 1);
              if (newPage > 1) _ensurePageSurahsLoaded(newPage - 1);
              setState(() {});
            },
            itemBuilder: (context, index) {
              final pageNumber = index + 1;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: FittedBox(
                  fit: BoxFit.contain,
                  alignment: Alignment.center,
                  child: _buildPageCanvas(pageNumber, c, app),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  /// Canonical 794x1123 Virtual Mushaf Canvas:
  /// - Exact A4 Medina Mushaf aspect ratio (0.707).
  /// - Scaled uniformly via FittedBox(fit: BoxFit.contain) so it NEVER overflows.
  /// - On mobile/narrow screens: smoothly scales down with zero clipping.
  /// - On tablet/wide screens: displays two spreads side-by-side like a real opened book.
  Widget _buildPageCanvas(int pageNumber, ThemeColors c, AppState app) {
    final lines = _mushafPagesCache?[pageNumber] ?? [];

    return Container(
      width: basePageWidth,
      height: basePageHeight,
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.border.withValues(alpha: 0.35), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // ── 15 Lines Container ──
          Expanded(
            child: lines.isEmpty
                ? const SizedBox.shrink()
                : LayoutBuilder(
                    builder: (context, lineConstraints) {
                      final lineWidth = lineConstraints.maxWidth;

                      if (pageNumber <= 2) {
                        return Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(lines.length, (lineIndex) {
                            final nextLine = lineIndex + 1 < lines.length ? lines[lineIndex + 1] : null;
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: _buildLineRow(
                                lineData: lines[lineIndex],
                                nextLineData: nextLine,
                                lineIndex: lineIndex,
                                totalLines: lines.length,
                                pageNumber: pageNumber,
                                lineWidth: lineWidth,
                                fontSize: baseFontSize,
                                c: c,
                                app: app,
                              ),
                            );
                          }),
                        );
                      }

                      // Standard 15-line pages: each line has an equal Expanded slot
                      return Column(
                        children: List.generate(lines.length, (lineIndex) {
                          final nextLine = lineIndex + 1 < lines.length ? lines[lineIndex + 1] : null;
                          return Expanded(
                            child: Center(
                              child: _buildLineRow(
                                lineData: lines[lineIndex],
                                nextLineData: nextLine,
                                lineIndex: lineIndex,
                                totalLines: lines.length,
                                pageNumber: pageNumber,
                                lineWidth: lineWidth,
                                fontSize: baseFontSize,
                                c: c,
                                app: app,
                              ),
                            ),
                          );
                        }),
                      );
                    },
                  ),
          ),

          // ── Single Centered Page Number at the Bottom ──
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 2),
            child: Center(
              child: Text(
                _toArabicDigits(pageNumber),
                style: TextStyle(
                  fontFamily: 'HafsSmart',
                  fontSize: 22.0,
                  color: c.gold,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLineRow({
    required Map<String, dynamic> lineData,
    required Map<String, dynamic>? nextLineData,
    required int lineIndex,
    required int totalLines,
    required int pageNumber,
    required double lineWidth,
    required double fontSize,
    required ThemeColors c,
    required AppState app,
  }) {
    final type = lineData['t'] as String?;

    // 1. Surah Header Line (ONLY at the first of the Surah)
    if (type == 'header') {
      final surahNum = lineData['s'] as int? ?? 1;
      final surahName = lineData['name'] as String? ?? 'سورة $surahNum';

      return SizedBox(
        width: lineWidth,
        child: Center(
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 2),
            padding: const EdgeInsets.symmetric(vertical: 3.5, horizontal: 28),
            decoration: BoxDecoration(
              color: c.gold.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: c.gold.withValues(alpha: 0.35), width: 1.2),
            ),
            child: Text(
              surahName,
              style: TextStyle(
                fontFamily: 'HafsSmart',
                fontSize: fontSize * 0.65,
                fontWeight: FontWeight.w700,
                color: c.gold,
              ),
              textDirection: TextDirection.rtl,
            ),
          ),
        ),
      );
    }

    // 2. Basmala Line
    if (type == 'basmala') {
      return SizedBox(
        width: lineWidth,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                'بِسْمِ ٱللَّهِ ٱلرَّحْمَـٰنِ ٱلرَّحِيمِ',
                style: TextStyle(
                  fontFamily: 'HafsSmart',
                  fontSize: fontSize * 0.88,
                  fontWeight: FontWeight.w700,
                  color: c.text,
                ),
                textDirection: TextDirection.rtl,
              ),
            ),
          ),
        ),
      );
    }

    // 3. Text Line with Words and Circular Ayah Numbers
    final wordsLoc = (lineData['w'] as List?)?.map((e) => e.toString()).toList() ?? [];
    if (wordsLoc.isEmpty) return const SizedBox.shrink();

    // Exact justification rule from mushaf-svelte:
    final bool nextLineIsHeader = nextLineData != null && nextLineData['t'] == 'header';
    final bool isLastLineOfPage = lineIndex == totalLines - 1;
    final bool shouldJustify = pageNumber > 2 &&
        !nextLineIsHeader &&
        (!isLastLineOfPage || pageNumber <= 599);

    final wordWidgets = <Widget>[];

    for (int i = 0; i < wordsLoc.length; i++) {
      final loc = wordsLoc[i];
      final parts = loc.split(':');
      if (parts.length < 3) continue;

      final surah = int.parse(parts[0]);
      final ayah = int.parse(parts[1]);
      final wordIndex1 = int.parse(parts[2]);
      final wordIndex0 = wordIndex1 - 1;

      final surahVerses = widget.controller.repository.getSurah(surah);
      if (surahVerses.isEmpty) continue;

      final verseIdx = surahVerses.indexWhere((v) => v.ayah == ayah);
      if (verseIdx < 0) continue;

      final verse = surahVerses[verseIdx];
      if (wordIndex0 >= verse.uthmaniWords.length) continue;

      final wordText = verse.uthmaniWords[wordIndex0];

      final isRead = widget.controller.isWordGreen(ayah, wordIndex0) ||
          widget.controller.isWordRed(ayah, wordIndex0) ||
          widget.controller.isWordYellow(ayah, wordIndex0) ||
          widget.controller.isWordNeutral(ayah, wordIndex0);

      final isHidden = app.isBlurMode && !isRead && !widget.isAutoScrolling;

      final Color textColor = isHidden
          ? Colors.transparent
          : VerseSpanBuilder.resolveWordColor(
              ayah: ayah,
              wordIndex: wordIndex0,
              controller: widget.controller,
              colors: c,
            );

      final activeMatch = widget.controller.currentMatchedVerse;
      final bool isVerseActive = widget.isRecording &&
          activeMatch != null &&
          activeMatch.verse.surah == surah &&
          activeMatch.verse.ayah == ayah;

      bool isWordActive = false;
      if (isVerseActive) {
        int targetIdx = -1;
        for (int w = 0; w < verse.uthmaniWords.length; w++) {
          if (!widget.controller.isWordGreen(ayah, w) &&
              !widget.controller.isWordRed(ayah, w) &&
              !widget.controller.isWordYellow(ayah, w) &&
              !widget.controller.isWordNeutral(ayah, w)) {
            targetIdx = w;
            break;
          }
        }
        isWordActive = (targetIdx == wordIndex0);
      }

      wordWidgets.add(
        GestureDetector(
          onTap: () => _handleWordTap(surah, ayah, wordIndex0, wordText),
          behavior: HitTestBehavior.opaque,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 1.5, vertical: 1.0),
            decoration: isWordActive
                ? BoxDecoration(
                    color: c.wordHighlight.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  )
                : null,
            child: Text(
              wordText,
              style: TextStyle(
                fontFamily: 'HafsSmart',
                fontSize: fontSize,
                color: textColor,
                height: 1.25,
              ),
            ),
          ),
        ),
      );

      // If this is the last word of the Ayah, add the Ayah Number in a Circle
      final bool isLastWordOfAyah = wordIndex1 == verse.uthmaniWords.length;
      if (isLastWordOfAyah) {
        wordWidgets.add(
          GestureDetector(
            onTap: () => widget.controller.setManualAyah(surah, ayah),
            behavior: HitTestBehavior.opaque,
            child: _buildAyahCircle(ayah, fontSize, c),
          ),
        );
      }
    }

    // Exact Svelte row distribution: words fill the full lineWidth via spaceBetween.
    // FittedBox(scaleDown) with width: lineWidth provides a safety valve so
    // that standard lines are rendered at full 100% font size without distortion.
    return SizedBox(
      width: lineWidth,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.center,
        child: SizedBox(
          width: lineWidth,
          child: Row(
            textDirection: TextDirection.rtl,
            mainAxisAlignment: shouldJustify ? MainAxisAlignment.spaceBetween : MainAxisAlignment.center,
            children: wordWidgets,
          ),
        ),
      ),
    );
  }

  /// Circular badge displaying the Ayah number at the end of each verse
  Widget _buildAyahCircle(int ayah, double fontSize, ThemeColors c) {
    final double size = fontSize * 0.78;
    return Container(
      width: size,
      height: size,
      margin: const EdgeInsets.symmetric(horizontal: 1.5),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: c.gold.withValues(alpha: 0.8),
          width: 1.2,
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        _toArabicDigits(ayah),
        style: TextStyle(
          fontFamily: 'HafsSmart',
          fontSize: fontSize * 0.42,
          color: c.gold,
          fontWeight: FontWeight.w700,
          height: 1.0,
        ),
      ),
    );
  }
}
