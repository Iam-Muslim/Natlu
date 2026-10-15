import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:recite_quran/recite_quran.dart';

import '../../../../state/app_state.dart';
import '../../verse_row.dart';
import '../data/mushaf_repository.dart';
import '../models/mushaf_models.dart';
import 'mushaf_line.dart';

/// Authentic Mushaf Page Layout:
/// - Single RepaintBoundary per page (eliminates 48 offscreen GPU layer allocations).
/// - Scoped State: Only subscribes to and rebuilds on events affecting THIS specific page.
/// - Instant native flex justification via Row + MainAxisAlignment.spaceBetween.
/// - Zero TextPainter.layout() calls on the UI thread for instant 60-120 FPS swiping.
class MushafPage extends StatefulWidget {
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

  const MushafPage({
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
  State<MushafPage> createState() => _MushafPageState();
}

class _MushafPageState extends State<MushafPage> {
  final List<GlobalKey> _lineKeys = List.generate(16, (_) => GlobalKey());

  bool _hadActiveReciter = false;
  bool _hadActiveAudio = false;
  bool _lastBlurMode = false;

  Widget? _cachedIdlePageWidget;
  double? _cachedMaxWidth;
  double? _cachedMaxHeight;
  Color? _cachedTextColor;


  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didUpdateWidget(MushafPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _unsubscribe(oldWidget.controller);
      _subscribe();
    }
    if (oldWidget.isAutoScrolling != widget.isAutoScrolling ||
        oldWidget.isRecording != widget.isRecording ||
        oldWidget.wordFontFamily != widget.wordFontFamily ||
        oldWidget.ayahMarkerFontFamily != widget.ayahMarkerFontFamily ||
        oldWidget.showAyahMarkerCircle != widget.showAyahMarkerCircle ||
        oldWidget.showBottomPageNumber != widget.showBottomPageNumber ||
        oldWidget.ayahMarkerBorderWidth != widget.ayahMarkerBorderWidth ||
        oldWidget.ayahMarkerBorderColor != widget.ayahMarkerBorderColor ||
        oldWidget.ayahMarkerTextColor != widget.ayahMarkerTextColor) {
      _lastFingerprint = -1;
      _cachedIdlePageWidget = null;
      setState(() {});
    }
  }

  void _subscribe() {
    widget.controller.addListener(_onRelevantChange);
    AppState.instance.blurModeNotifier.addListener(_onBlurModeChanged);
    AppState.instance.activeAudioAyah.addListener(_onRelevantChange);
    AppState.instance.activeAudioSurah.addListener(_onRelevantChange);
    AppState.instance.activeAudioWordIndex.addListener(_onRelevantChange);
    AppState.instance.isAudioPlaying.addListener(_onRelevantChange);
    AppState.instance.isAudioBuffering.addListener(_onRelevantChange);
  }

  void _unsubscribe(HighlightingController controller) {
    controller.removeListener(_onRelevantChange);
    AppState.instance.blurModeNotifier.removeListener(_onBlurModeChanged);
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
    final repo = MushafRepository.instance;

    final int? activeAyah = ctrl.activeAyah.value;
    final int targetSurah =
        ctrl.targetSurah != 0 ? ctrl.targetSurah : app.lastSurah;
    final int? audioAyah = app.activeAudioAyah.value;
    final int? audioSurah = app.activeAudioSurah.value;

    final bool reciterOnThisPage = activeAyah != null &&
        repo.isAyahOnPage(
            pageNumber: widget.pageNumber,
            surah: targetSurah,
            ayah: activeAyah);
    final bool audioOnThisPage = audioAyah != null &&
        audioSurah != null &&
        repo.isAyahOnPage(
            pageNumber: widget.pageNumber,
            surah: audioSurah,
            ayah: audioAyah);

    if (!reciterOnThisPage && !audioOnThisPage) {
      int idleHash = (_hadActiveReciter || _hadActiveAudio) ? 1 : 0;
      idleHash = idleHash * 31 + ctrl.globalRevision.value;
      idleHash = idleHash * 31 + (app.isBlurMode ? 1 : 0);
      return idleHash;
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
    hash = hash * 31 + (app.isBlurMode ? 1 : 0);
    hash = hash * 31 + ctrl.globalRevision.value;

    if (reciterOnThisPage) {
      final words = MushafRepository.instance.verseWordsMemoryCache['$targetSurah:$activeAyah'];
      final int wordCount = words?.length ?? 30;
      for (int i = 0; i < wordCount; i++) {
        if (ctrl.isWordGreen(activeAyah, i, surah: targetSurah)) {
          hash = hash * 31 + (i + 1) * 7;
        } else if (ctrl.isWordRed(activeAyah, i, surah: targetSurah)) {
          hash = hash * 31 + (i + 1) * 13;
        } else if (ctrl.isWordYellow(activeAyah, i, surah: targetSurah)) {
          hash = hash * 31 + (i + 1) * 17;
        } else if (ctrl.isWordNeutral(activeAyah, i, surah: targetSurah)) {
          hash = hash * 31 + (i + 1) * 23;
        }
      }
      final matched = ctrl.currentMatchedVerse;
      if (matched != null) {
        hash = hash * 31 + matched.verse.ayah;
      }
    }

    return hash;
  }

  void _onBlurModeChanged() {
    if (!mounted) return;
    final bool currentBlur = AppState.instance.isBlurMode;
    if (_lastBlurMode != currentBlur) {
      _lastBlurMode = currentBlur;
      _lastFingerprint = -1;
      setState(() {});
    }
  }

  void _onRelevantChange() {
    if (!mounted) return;

    final repo = MushafRepository.instance;
    final int? activeAyah = widget.controller.activeAyah.value;
    final int targetSurah = widget.controller.targetSurah != 0
        ? widget.controller.targetSurah
        : AppState.instance.lastSurah;
    final int? audioAyah = AppState.instance.activeAudioAyah.value;
    final int? audioSurah = AppState.instance.activeAudioSurah.value;

    final bool reciterOnThisPage = activeAyah != null &&
        repo.isAyahOnPage(
            pageNumber: widget.pageNumber,
            surah: targetSurah,
            ayah: activeAyah);
    final bool audioOnThisPage = audioAyah != null &&
        audioSurah != null &&
        repo.isAyahOnPage(
            pageNumber: widget.pageNumber,
            surah: audioSurah,
            ayah: audioAyah);

    // Exit immediately if this page is completely idle
    if (!reciterOnThisPage &&
        !audioOnThisPage &&
        !_hadActiveReciter &&
        !_hadActiveAudio) {
      return;
    }

    _hadActiveReciter = reciterOnThisPage;
    _hadActiveAudio = audioOnThisPage;

    // During active recording: every notification represents an ASR word match or progress update!
    if (reciterOnThisPage && widget.isRecording) {
      _cachedIdlePageWidget = null;
      setState(() {});
      return;
    }

    final fp = _computePageFingerprint();
    if (fp != _lastFingerprint) {
      _lastFingerprint = fp;
      _cachedIdlePageWidget = null;
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppState.instance;
    final c = app.colors;
    final repo = MushafRepository.instance;
    final lines = repo.getLinesForPage(widget.pageNumber);

    if (lines.isEmpty) return const SizedBox.shrink();

    final ctrl = widget.controller;
    final int? activeAyah = ctrl.activeAyah.value;
    final int targetSurah =
        ctrl.targetSurah != 0 ? ctrl.targetSurah : app.lastSurah;
    final int? audioAyah = app.activeAudioAyah.value;
    final int? audioSurah = app.activeAudioSurah.value;

    final bool reciterOnThisPage = activeAyah != null &&
        repo.isAyahOnPage(
            pageNumber: widget.pageNumber,
            surah: targetSurah,
            ayah: activeAyah);
    final bool audioOnThisPage = audioAyah != null &&
        audioSurah != null &&
        repo.isAyahOnPage(
            pageNumber: widget.pageNumber,
            surah: audioSurah,
            ayah: audioAyah);

    final bool isPageIdle = !reciterOnThisPage &&
        !audioOnThisPage &&
        !widget.isRecording &&
        !app.isBlurMode;

    return RepaintBoundary(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final double maxWidth = constraints.maxWidth;
          final double maxHeight = constraints.maxHeight;

          if (isPageIdle &&
              _cachedIdlePageWidget != null &&
              _cachedMaxWidth == maxWidth &&
              _cachedMaxHeight == maxHeight &&
              _cachedTextColor == c.text) {
            return _cachedIdlePageWidget!;
          }

          final bool isLandscape = maxWidth > maxHeight;

          final double bottomReserved = isLandscape ? 48.0 : 64.0;
          final double rawH = maxHeight - bottomReserved;
          final double availableHeight =
              math.max(40.0, math.min(rawH, maxHeight));
          final double availableWidth = math.max(40.0, maxWidth);

          final double lineWidth;
          final double linesContainerHeight;

          if (isLandscape) {
            const double mushafAspectRatio = 0.65;
            double h = availableHeight;
            double w = h * mushafAspectRatio;
            final double maxAllowedW = math.max(40.0, availableWidth - 24.0);
            if (w > maxAllowedW) {
              w = maxAllowedW;
              h = w / mushafAspectRatio;
            }
            lineWidth = math.max(40.0, w);
            linesContainerHeight = math.max(40.0, h);
          } else {
            // Portrait: Ayahs expand to fill full height right down to the bottom bar.
            final double maxW = math.max(40.0, availableWidth - 16.0);
            final double idealW = math.max(40.0, availableHeight * 0.72);
            lineWidth = math.min(maxW, idealW);
            linesContainerHeight = availableHeight;
          }

          final Widget pageContent;

          // Pages 1 & 2 special centered layout (Al-Fatihah and start of Al-Baqarah)
          if (widget.pageNumber <= 2) {
            final double idealLineHeight =
                linesContainerHeight / (lines.length + 3);
            final double maxH = math.max(16.0, idealLineHeight);
            final double baseLineHeight =
                idealLineHeight.clamp(math.min(24.0, maxH), 72.0);

            int headerCount = 0;
            int basmalaCount = 0;
            int textCount = 0;
            int maxWordsOnPage = 0;
            for (final line in lines) {
              final t = line['t'] as String?;
              if (t == 'header') {
                headerCount++;
              } else if (t == 'basmala') {
                basmalaCount++;
              } else {
                textCount++;
                final pw = line['parsed_words'] as List<MushafWordRef>? ?? const [];
                if (pw.length > maxWordsOnPage) {
                  maxWordsOnPage = pw.length;
                }
              }
            }
            if (maxWordsOnPage == 0) maxWordsOnPage = 6;

            final double headerLineHeight =
                (baseLineHeight * 0.74).clamp(24.0, 48.0);
            final double basmalaLineHeight =
                (baseLineHeight * 0.52).clamp(18.0, 36.0);
            final double specialTotalH = (headerCount * headerLineHeight) +
                (basmalaCount * basmalaLineHeight);
            final double totalContentH = baseLineHeight * lines.length;
            final double textLineHeight =
                (textCount > 0 && (headerCount > 0 || basmalaCount > 0))
                    ? (totalContentH - specialTotalH) / textCount
                    : baseLineHeight;

            final double maxP1FontFromHeight = math.max(8.0, textLineHeight * 0.48);
            final double maxP1FontFromWidth =
                (lineWidth - 16.0) / (maxWordsOnPage * 2.05 + 1.2);
            final double fontSize = math.min(maxP1FontFromHeight, maxP1FontFromWidth)
                .clamp(11.0, 23.0);

            pageContent = Directionality(
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
                              final lineData = lines[lineIndex];
                              final t = lineData['t'] as String?;
                              final double thisLineHeight = t == 'header'
                                  ? headerLineHeight
                                  : t == 'basmala'
                                      ? basmalaLineHeight
                                      : textLineHeight;
                              return SizedBox(
                                width: lineWidth,
                                height: thisLineHeight,
                                child: MushafLine(
                                  lineData: lineData,
                                  nextLineData: nextLine,
                                  lineIndex: lineIndex,
                                  totalLines: lines.length,
                                  pageNumber: widget.pageNumber,
                                  lineWidth: lineWidth,
                                  lineHeight: thisLineHeight,
                                  fontSize: fontSize,
                                  colors: c,
                                  app: app,
                                  isPageIdle: isPageIdle,
                                  controller: widget.controller,
                                  isRecording: widget.isRecording,
                                  isAutoScrolling: widget.isAutoScrolling,
                                  wordFontFamily: widget.wordFontFamily,
                                  ayahMarkerFontFamily: widget.ayahMarkerFontFamily,
                                  ayahMarkerBorderColor: widget.ayahMarkerBorderColor,
                                  ayahMarkerTextColor: widget.ayahMarkerTextColor,
                                  ayahMarkerBorderWidth: widget.ayahMarkerBorderWidth,
                                  showAyahMarkerCircle: widget.showAyahMarkerCircle,
                                  lineKey: _lineKeys[lineIndex < _lineKeys.length ? lineIndex : 0],
                                  verseWordsMemoryCache: MushafRepository.instance.verseWordsMemoryCache,
                                  onStateChangeRequested: () {
                                    if (mounted) setState(() {});
                                  },
                                ),
                              );
                            }),
                          ),
                        ),
                      ),
                      if (widget.showBottomPageNumber)
                        Positioned(
                          left: 14,
                          bottom: 8,
                          child:
                              _buildBottomPageNumber(widget.pageNumber, c),
                        ),
                    ],
                  ),
                ),
              ),
            );
          } else {
            // Standard 15-line Mushaf pages
            final double baseLineHeight = linesContainerHeight / lines.length;

            int headerCount = 0;
            int basmalaCount = 0;
            int textCount = 0;
            int maxWordsOnPage = 0;
            for (final line in lines) {
              final t = line['t'] as String?;
              if (t == 'header') {
                headerCount++;
              } else if (t == 'basmala') {
                basmalaCount++;
              } else {
                textCount++;
                final pw = line['parsed_words'] as List<MushafWordRef>? ?? const [];
                if (pw.length > maxWordsOnPage) {
                  maxWordsOnPage = pw.length;
                }
              }
            }
            if (maxWordsOnPage == 0) maxWordsOnPage = 10;

            final double headerLineHeight =
                (baseLineHeight * 0.74).clamp(24.0, 36.0);
            final double basmalaLineHeight =
                (baseLineHeight * 0.52).clamp(18.0, 26.0);

            final double specialTotalH = (headerCount * headerLineHeight) +
                (basmalaCount * basmalaLineHeight);
            final double textLineHeight =
                (textCount > 0 && (headerCount > 0 || basmalaCount > 0))
                    ? (linesContainerHeight - specialTotalH) / textCount
                    : baseLineHeight;

            final double maxStandardFontFromHeight =
                math.max(8.0, textLineHeight * 0.50);
            final double maxStandardFontFromWidth =
                (lineWidth - 14.0) / (maxWordsOnPage * 1.90 + 1.2);
            final double fontSize =
                math.min(maxStandardFontFromHeight, maxStandardFontFromWidth)
                    .clamp(11.0, 24.0);

            pageContent = Directionality(
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
                        child: SizedBox(
                          width: lineWidth,
                          height: linesContainerHeight,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: List.generate(lines.length, (lineIndex) {
                              final nextLine = lineIndex + 1 < lines.length
                                  ? lines[lineIndex + 1]
                                  : null;
                              final lineData = lines[lineIndex];
                              final t = lineData['t'] as String?;
                              final double thisLineHeight = t == 'header'
                                  ? headerLineHeight
                                  : t == 'basmala'
                                      ? basmalaLineHeight
                                      : textLineHeight;
                              return SizedBox(
                                width: lineWidth,
                                height: thisLineHeight,
                                child: MushafLine(
                                  lineData: lineData,
                                  nextLineData: nextLine,
                                  lineIndex: lineIndex,
                                  totalLines: lines.length,
                                  pageNumber: widget.pageNumber,
                                  lineWidth: lineWidth,
                                  lineHeight: thisLineHeight,
                                  fontSize: fontSize,
                                  colors: c,
                                  app: app,
                                  isPageIdle: isPageIdle,
                                  controller: widget.controller,
                                  isRecording: widget.isRecording,
                                  isAutoScrolling: widget.isAutoScrolling,
                                  wordFontFamily: widget.wordFontFamily,
                                  ayahMarkerFontFamily: widget.ayahMarkerFontFamily,
                                  ayahMarkerBorderColor: widget.ayahMarkerBorderColor,
                                  ayahMarkerTextColor: widget.ayahMarkerTextColor,
                                  ayahMarkerBorderWidth: widget.ayahMarkerBorderWidth,
                                  showAyahMarkerCircle: widget.showAyahMarkerCircle,
                                  lineKey: _lineKeys[lineIndex < _lineKeys.length ? lineIndex : 0],
                                  verseWordsMemoryCache: MushafRepository.instance.verseWordsMemoryCache,
                                  onStateChangeRequested: () {
                                    if (mounted) setState(() {});
                                  },
                                ),
                              );
                            }),
                          ),
                        ),
                      ),
                      if (widget.showBottomPageNumber)
                        Positioned(
                          left: 14,
                          bottom: 8,
                          child:
                              _buildBottomPageNumber(widget.pageNumber, c),
                        ),
                    ],
                  ),
                ),
              ),
            );
          }

          if (isPageIdle) {
            _cachedIdlePageWidget = pageContent;
            _cachedMaxWidth = maxWidth;
            _cachedMaxHeight = maxHeight;
            _cachedTextColor = c.text;
          } else {
            _cachedIdlePageWidget = null;
          }

          return pageContent;
        },
      ),
    );
  }

  Widget _buildBottomPageNumber(int pageNumber, ThemeColors c) {
    return Text(
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
    );
  }
}
