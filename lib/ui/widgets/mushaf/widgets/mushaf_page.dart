import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:recite_quran/recite_quran.dart';

import '../../../../state/app_state.dart';
import '../../verse_row.dart';
import '../data/mushaf_repository.dart';
import '../models/mushaf_models.dart';
import 'mushaf_basmala.dart';
import 'mushaf_line.dart';
import 'mushaf_surah_header.dart';

/// Authentic Mushaf Page Layout:
/// - Native 15-flex Expanded Column where each line occupies an equal vertical slot.
/// - Single uniform [baseFontSize] across all standard pages and lines.
/// - 0ms instantaneous page transitions (no blank deferral during swipe).
/// - Single RepaintBoundary per page.
/// - Visited pages remain cached in GPU memory via [AutomaticKeepAliveClientMixin].
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
  final ValueListenable<bool>? deferWhile;

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
    this.deferWhile,
  });

  @override
  State<MushafPage> createState() => _MushafPageState();
}

class _MushafPageState extends State<MushafPage>
    with AutomaticKeepAliveClientMixin<MushafPage> {
  @override
  bool get wantKeepAlive => true;

  bool _hadActiveReciter = false;
  bool _hadActiveAudio = false;

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
  }

  void _subscribe() {
    widget.controller.addListener(_onRelevantChange);
    AppState.instance.blurModeNotifier.addListener(_onRelevantChange);
    AppState.instance.activeAudioAyah.addListener(_onRelevantChange);
    AppState.instance.activeAudioSurah.addListener(_onRelevantChange);
    AppState.instance.activeAudioWordIndex.addListener(_onRelevantChange);
    AppState.instance.isAudioPlaying.addListener(_onRelevantChange);
    AppState.instance.isAudioBuffering.addListener(_onRelevantChange);
  }

  void _unsubscribe(HighlightingController controller) {
    controller.removeListener(_onRelevantChange);
    AppState.instance.blurModeNotifier.removeListener(_onRelevantChange);
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

    if (!reciterOnThisPage &&
        !audioOnThisPage &&
        !_hadActiveReciter &&
        !_hadActiveAudio) {
      return;
    }

    _hadActiveReciter = reciterOnThisPage;
    _hadActiveAudio = audioOnThisPage;

    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final app = AppState.instance;
    final c = app.colors;
    final repo = MushafRepository.instance;
    final lines = repo.getLinesForPage(widget.pageNumber);

    if (lines.isEmpty) return const SizedBox.shrink();

    return RepaintBoundary(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final double maxWidth = constraints.maxWidth;
          final double maxHeight = constraints.maxHeight;

          final double bottomReserved = widget.showBottomPageNumber ? 24.0 : 4.0;
          final double linesContainerHeight = math.max(40.0, maxHeight - bottomReserved);
          final double maxMushafW = math.min(maxWidth - 16.0, linesContainerHeight * 0.72);
          final double lineWidth = math.max(40.0, maxMushafW);

          // Uniform 15-flex Mushaf geometry:
          // Every page has exactly 15 line slots.
          final double lineSlotHeight = linesContainerHeight / 15.0;
          // Base font size is UNIFORM across all lines and pages:
          final double baseFontSize = (lineSlotHeight * 0.54).clamp(18.0, 27.5);

          int flexCount = 0;
          final List<Widget> flexChildren = [];

          for (int lineIndex = 0; lineIndex < lines.length; lineIndex++) {
            final lineData = lines[lineIndex];
            final nextLine =
                lineIndex + 1 < lines.length ? lines[lineIndex + 1] : null;
            final t = lineData['t'] as String?;

            if (t == 'header') {
              final surahNum = lineData['s'] as int? ?? 1;
              String surahName =
                  lineData['name'] as String? ?? 'سورة $surahNum';
              if (surahNum >= 1 &&
                  surahNum <=
                      widget.controller.repository.surahMetadata.length) {
                final meta = widget
                    .controller.repository.surahMetadata[surahNum - 1];
                if (meta.surahName.isNotEmpty) {
                  final rawName = meta.surahName;
                  surahName = rawName.startsWith('سورة') ||
                          rawName.startsWith('سُورَة')
                      ? rawName
                      : 'سورة $rawName';
                }
              }

              flexChildren.add(
                Expanded(
                  child: Center(
                    child: MushafSurahHeader(
                      surahNum: surahNum,
                      surahName: surahName,
                      lineWidth: lineWidth,
                      lineHeight: lineSlotHeight,
                      fontSize: baseFontSize,
                      colors: c,
                      app: app,
                      controller: widget.controller,
                      onAyahSelected: () {
                        if (mounted) setState(() {});
                      },
                    ),
                  ),
                ),
              );
              flexCount++;
            } else if (t == 'basmala') {
              int basmalaSurah = 1;
              if (nextLine != null && nextLine['parsed_words'] is List) {
                final pw = nextLine['parsed_words'] as List<MushafWordRef>;
                if (pw.isNotEmpty) basmalaSurah = pw.first.surah;
              }

              flexChildren.add(
                Expanded(
                  child: Center(
                    child: MushafBasmala(
                      basmalaSurah: basmalaSurah,
                      lineWidth: lineWidth,
                      lineHeight: lineSlotHeight,
                      fontSize: baseFontSize,
                      wordFontFamily: widget.wordFontFamily,
                      colors: c,
                      controller: widget.controller,
                      isAutoScrolling: widget.isAutoScrolling,
                      onAyahSelected: () {
                        if (mounted) setState(() {});
                      },
                    ),
                  ),
                ),
              );
              flexCount++;
            } else {
              // Standard justified text line via MushafHighlightRow
              flexChildren.add(
                Expanded(
                  child: Center(
                    child: MushafLine(
                      lineData: lineData,
                      nextLineData: nextLine,
                      lineIndex: lineIndex,
                      totalLines: lines.length,
                      pageNumber: widget.pageNumber,
                      lineWidth: lineWidth,
                      lineHeight: lineSlotHeight,
                      fontSize: baseFontSize,
                      wordFontFamily: widget.wordFontFamily,
                      ayahMarkerFontFamily: widget.ayahMarkerFontFamily,
                      ayahMarkerBorderColor: widget.ayahMarkerBorderColor,
                      ayahMarkerTextColor: widget.ayahMarkerTextColor,
                      ayahMarkerBorderWidth: widget.ayahMarkerBorderWidth,
                      showAyahMarkerCircle: widget.showAyahMarkerCircle,
                      controller: widget.controller,
                      isRecording: widget.isRecording,
                      isAutoScrolling: widget.isAutoScrolling,
                      colors: c,
                      app: app,
                      onStateChangeRequested: () {
                        if (mounted) setState(() {});
                      },
                    ),
                  ),
                ),
              );
              flexCount++;
            }
          }

          final List<Widget> columnChildren = [];

          // Pages 1 & 2 special centering
          if (widget.pageNumber <= 2) {
            final int emptyFlex = (15 - flexCount).clamp(0, 15);
            final int topEmpty = emptyFlex ~/ 2;
            final int bottomEmpty = emptyFlex - topEmpty;
            if (topEmpty > 0) columnChildren.add(Spacer(flex: topEmpty));
            columnChildren.addAll(flexChildren);
            if (bottomEmpty > 0) columnChildren.add(Spacer(flex: bottomEmpty));
          } else {
            columnChildren.addAll(flexChildren);
            if (flexCount < 15) {
              columnChildren.add(Spacer(flex: 15 - flexCount));
            }
          }

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
                      child: SizedBox(
                        width: lineWidth,
                        height: linesContainerHeight,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: columnChildren,
                        ),
                      ),
                    ),
                    if (widget.showBottomPageNumber)
                      Positioned(
                        left: 14,
                        bottom: 6,
                        child: _buildBottomPageNumber(widget.pageNumber, c),
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
