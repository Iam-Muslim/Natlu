import 'package:flutter/material.dart';
import 'package:recite_quran/recite_quran.dart';

import '../../../../state/app_state.dart';
import '../../helpers/verse_span_builder.dart';
import '../../verse_row.dart';
import '../data/mushaf_repository.dart';
import '../models/mushaf_models.dart';
import 'mushaf_ayah_marker.dart';
import 'mushaf_highlight_row.dart';

/// Authentic 15-line Mushaf Line Widget:
/// - Uses [MushafHighlightRow] to distribute words edge-to-edge ([MainAxisAlignment.spaceBetween]).
/// - Uniform typographic scale: all words and Ayah markers use the exact [fontSize] calculated for the page.
/// - Ayah markers maintain strict 1:1 squircle proportions and never distort.
/// - Centered only when appropriate (pages 1 & 2, or the final line of a Surah).
/// - Wrapped in [BoxFit.scaleDown] so long lines shrink gently to fit width, but short lines never scale up into giant text.
class MushafLine extends StatelessWidget {
  final Map<String, dynamic> lineData;
  final Map<String, dynamic>? nextLineData;
  final int lineIndex;
  final int totalLines;
  final int pageNumber;
  final double? lineWidth;
  final double? lineHeight;
  final double? fontSize;
  final ThemeColors colors;
  final AppState app;
  final HighlightingController controller;
  final bool isRecording;
  final bool isAutoScrolling;
  final String wordFontFamily;
  final String? ayahMarkerFontFamily;
  final Color? ayahMarkerBorderColor;
  final Color? ayahMarkerTextColor;
  final double ayahMarkerBorderWidth;
  final bool showAyahMarkerCircle;
  final Map<String, List<String>>? verseWordsMemoryCache;
  final VoidCallback onStateChangeRequested;

  const MushafLine({
    super.key,
    required this.lineData,
    this.nextLineData,
    required this.lineIndex,
    required this.totalLines,
    required this.pageNumber,
    this.lineWidth,
    this.lineHeight,
    this.fontSize,
    required this.colors,
    required this.app,
    required this.controller,
    required this.isRecording,
    required this.isAutoScrolling,
    required this.wordFontFamily,
    this.ayahMarkerFontFamily,
    this.ayahMarkerBorderColor,
    this.ayahMarkerTextColor,
    this.ayahMarkerBorderWidth = 1.2,
    this.showAyahMarkerCircle = true,
    this.verseWordsMemoryCache,
    required this.onStateChangeRequested,
  });

  @override
  Widget build(BuildContext context) {
    final parsedWords =
        lineData['parsed_words'] as List<MushafWordRef>? ?? const [];
    if (parsedWords.isEmpty) return const SizedBox.shrink();

    // Centered rules: ONLY page 1 & 2, the final line before a new Surah starts, or page 604 last line.
    final bool nextLineIsHeader =
        nextLineData != null && nextLineData!['t'] == 'header';
    final bool isLastLineOfPage = lineIndex == totalLines - 1;
    final bool isCentered = pageNumber <= 2 ||
        nextLineIsHeader ||
        (pageNumber == 604 && isLastLineOfPage);

    final double effectiveFontSize = fontSize ?? 24.0;

    final TextStyle defaultWordStyle = TextStyle(
      fontFamily: wordFontFamily,
      fontSize: effectiveFontSize,
      color: colors.text,
      height: 1.25,
    );

    final cache = verseWordsMemoryCache ??
        MushafRepository.instance.verseWordsMemoryCache;
    final bool isDark = app.isDarkMode;

    final List<Widget> wordWidgets = [];
    int? highlightStartIndex;
    int? highlightEndIndex;

    int lastCachedSurah = -1;
    int lastCachedAyah = -1;
    List<String>? cachedWords;
    bool cachedIsAyahActive = false;
    int cachedTargetIndex = -1;
    bool cachedIsCompleted = false;

    for (int i = 0; i < parsedWords.length; i++) {
      final ref = parsedWords[i];
      final int surah = ref.surah;
      final int ayah = ref.ayah;
      final int wordIndex0 = ref.wordIndex0;
      final int wordIndex1 = ref.wordIndex1;

      if (surah != lastCachedSurah || ayah != lastCachedAyah) {
        lastCachedSurah = surah;
        lastCachedAyah = ayah;

        final ayahKey = '$surah:$ayah';
        var words = cache[ayahKey];
        if (words == null) {
          final v = controller.repository.getVerse(surah, ayah);
          if (v != null) {
            words = v.uthmaniWords;
            cache[ayahKey] = words;
          }
        }
        cachedWords = words;

        final int effectiveTargetSurah = controller.targetSurah != 0
            ? controller.targetSurah
            : app.lastSurah;
        final bool isSelected = !isAutoScrolling &&
            effectiveTargetSurah == surah &&
            controller.activeAyah.value == ayah;
        final bool isRecitingActive = !isAutoScrolling &&
            controller.currentMatchedVerse?.verse.surah == surah &&
            controller.currentMatchedVerse?.verse.ayah == ayah;
        final bool isAudioActive = !isAutoScrolling &&
            VerseRow.isAyahAudioActive(surah: surah, ayah: ayah, app: app);
        cachedIsAyahActive = isSelected || isRecitingActive || isAudioActive;

        cachedTargetIndex = cachedIsAyahActive && cachedWords != null
            ? VerseRow.getTargetWordIndex(
                surah: surah,
                ayah: ayah,
                words: cachedWords,
                controller: controller,
                app: app,
                isRecording: isRecording,
                isActive: true,
              )
            : -1;
        cachedIsCompleted =
            controller.completedAyahsFor(surah).contains(ayah);
      }

      String? wordText = ref.text;
      if (wordText == null) {
        if (cachedWords != null && wordIndex0 < cachedWords.length) {
          wordText = cachedWords[wordIndex0];
          ref.text = wordText;
        } else {
          continue;
        }
      }
      final String resolvedWordText = wordText;

      final bool isWordActive = (cachedTargetIndex == wordIndex0);

      final Color textColor;
      final bool hasSessionHighlights = controller.globalRevision.value > 0;
      if (isRecording ||
          cachedIsAyahActive ||
          app.isBlurMode ||
          cachedIsCompleted ||
          hasSessionHighlights) {
        textColor = VerseSpanBuilder.resolveWordDisplayColor(
          ayah: ayah,
          wordIndex: wordIndex0,
          controller: controller,
          app: app,
          colors: colors,
          isAutoScrolling: isAutoScrolling,
          surah: surah,
        );
      } else {
        textColor = colors.text;
      }

      final int wordWidgetIndex = wordWidgets.length;
      if (cachedIsAyahActive) {
        highlightStartIndex ??= wordWidgetIndex;
        highlightEndIndex = wordWidgetIndex;
      }

      final BoxDecoration? wordDecoration = isWordActive
          ? BoxDecoration(
              color: colors.wordHighlight.withValues(
                alpha: isDark ? 0.22 : 0.26,
              ),
              borderRadius: BorderRadius.circular(4.0),
            )
          : null;

      final wordTextWidget = Text(
        resolvedWordText,
        textDirection: TextDirection.rtl,
        textScaler: TextScaler.noScaling,
        style: defaultWordStyle.copyWith(color: textColor),
      );

      final EdgeInsets wordPadding = EdgeInsets.symmetric(
        horizontal: isCentered ? 3.0 : 0.5,
        vertical: 1.0,
      );

      wordWidgets.add(
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            if (isAutoScrolling) return;
            VerseRow.handleWordTap(
              context: context,
              surah: surah,
              ayah: ayah,
              wordIndex: wordIndex0,
              wordText: resolvedWordText,
              controller: controller,
              isAutoScrolling: isAutoScrolling,
              onAyahTap: onStateChangeRequested,
            );
          },
          child: Container(
            padding: wordPadding,
            decoration: wordDecoration,
            child: wordTextWidget,
          ),
        ),
      );

      // Append Ayah number marker if this is the last word of this Ayah
      final bool isLastWordOfAyah = (cachedWords != null &&
              wordIndex1 == cachedWords.length) ||
          (i < parsedWords.length - 1 && parsedWords[i + 1].ayah != ayah) ||
          (i == parsedWords.length - 1 &&
              cachedWords != null &&
              wordIndex1 >= cachedWords.length);

      if (isLastWordOfAyah) {
        final int markerWidgetIndex = wordWidgets.length;
        if (cachedIsAyahActive) {
          highlightStartIndex ??= markerWidgetIndex;
          highlightEndIndex = markerWidgetIndex;
        }

        wordWidgets.add(
          MushafAyahMarker(
            surah: surah,
            ayah: ayah,
            fontSize: effectiveFontSize,
            isAyahActive: cachedIsAyahActive,
            colors: colors,
            app: app,
            controller: controller,
            isRecording: isRecording,
            isAutoScrolling: isAutoScrolling,
            ayahMarkerFontFamily: ayahMarkerFontFamily,
            ayahMarkerBorderColor: ayahMarkerBorderColor,
            ayahMarkerTextColor: ayahMarkerTextColor,
            ayahMarkerBorderWidth: ayahMarkerBorderWidth,
            showAyahMarkerCircle: showAyahMarkerCircle,
            onAudioToggled: onStateChangeRequested,
          ),
        );
      }
    }

    final row = MushafHighlightRow(
      mainAxisAlignment: isCentered
          ? MainAxisAlignment.center
          : MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: isCentered ? MainAxisSize.min : MainAxisSize.max,
      textDirection: TextDirection.rtl,
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
    );

    return SizedBox(
      width: lineWidth ?? double.infinity,
      height: lineHeight,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.center,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: isCentered ? 0.0 : (lineWidth ?? 0.0),
          ),
          child: row,
        ),
      ),
    );
  }
}
