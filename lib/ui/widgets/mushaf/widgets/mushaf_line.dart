import 'package:flutter/material.dart';
import 'package:recite_quran/recite_quran.dart';

import '../../../../state/app_state.dart';
import '../../helpers/verse_span_builder.dart';
import '../../verse_row.dart';
import '../models/mushaf_models.dart';
import 'mushaf_ayah_marker.dart';
import 'mushaf_basmala.dart';
import 'mushaf_highlight_row.dart';
import 'mushaf_surah_header.dart';

/// Renders a single line of a Mushaf page (header, basmala, or justified text).
class MushafLine extends StatelessWidget {
  final Map<String, dynamic> lineData;
  final Map<String, dynamic>? nextLineData;
  final int lineIndex;
  final int totalLines;
  final int pageNumber;
  final double lineWidth;
  final double lineHeight;
  final double fontSize;
  final ThemeColors colors;
  final AppState app;
  final bool isPageIdle;
  final HighlightingController controller;
  final bool isRecording;
  final bool isAutoScrolling;
  final String wordFontFamily;
  final String? ayahMarkerFontFamily;
  final Color? ayahMarkerBorderColor;
  final Color? ayahMarkerTextColor;
  final double ayahMarkerBorderWidth;
  final bool showAyahMarkerCircle;
  final GlobalKey lineKey;
  final Map<String, List<String>> verseWordsMemoryCache;
  final VoidCallback onStateChangeRequested;

  const MushafLine({
    super.key,
    required this.lineData,
    required this.nextLineData,
    required this.lineIndex,
    required this.totalLines,
    required this.pageNumber,
    required this.lineWidth,
    required this.lineHeight,
    required this.fontSize,
    required this.colors,
    required this.app,
    required this.isPageIdle,
    required this.controller,
    required this.isRecording,
    required this.isAutoScrolling,
    required this.wordFontFamily,
    this.ayahMarkerFontFamily,
    this.ayahMarkerBorderColor,
    this.ayahMarkerTextColor,
    this.ayahMarkerBorderWidth = 1.2,
    this.showAyahMarkerCircle = true,
    required this.lineKey,
    required this.verseWordsMemoryCache,
    required this.onStateChangeRequested,
  });

  @override
  Widget build(BuildContext context) {
    final type = lineData['t'] as String?;

    // 1. Surah Header Line
    if (type == 'header') {
      final surahNum = lineData['s'] as int? ?? 1;
      String surahName = lineData['name'] as String? ?? 'سورة $surahNum';
      if (surahNum >= 1 &&
          surahNum <= controller.repository.surahMetadata.length) {
        final meta = controller.repository.surahMetadata[surahNum - 1];
        if (meta.surahName.isNotEmpty) {
          final rawName = meta.surahName;
          surahName = rawName.startsWith('سورة') || rawName.startsWith('سُورَة')
              ? rawName
              : 'سورة $rawName';
        }
      }

      return MushafSurahHeader(
        surahNum: surahNum,
        surahName: surahName,
        lineWidth: lineWidth,
        lineHeight: lineHeight,
        fontSize: fontSize,
        colors: colors,
        app: app,
        controller: controller,
        onAyahSelected: onStateChangeRequested,
      );
    }

    // 2. Basmala Line
    if (type == 'basmala') {
      int basmalaSurah = 1;
      if (nextLineData != null && nextLineData!['parsed_words'] is List) {
        final pw = nextLineData!['parsed_words'] as List<MushafWordRef>;
        if (pw.isNotEmpty) {
          basmalaSurah = pw.first.surah;
        }
      }

      return MushafBasmala(
        basmalaSurah: basmalaSurah,
        lineWidth: lineWidth,
        lineHeight: lineHeight,
        fontSize: fontSize,
        wordFontFamily: wordFontFamily,
        colors: colors,
        controller: controller,
        isAutoScrolling: isAutoScrolling,
        onAyahSelected: onStateChangeRequested,
      );
    }

    // 3. Text Line with Words and Circular/Squircle Ayah End Numbers
    final parsedWords =
        lineData['parsed_words'] as List<MushafWordRef>? ?? const [];
    if (parsedWords.isEmpty) return const SizedBox.shrink();

    final bool nextLineIsHeader =
        nextLineData != null && nextLineData!['t'] == 'header';
    final bool isLastLineOfPage = lineIndex == totalLines - 1;
    final bool shouldJustify = pageNumber > 2 &&
        !nextLineIsHeader &&
        (!isLastLineOfPage || pageNumber <= 599) &&
        parsedWords.length >= 6;

    final bool isDark = app.isDarkMode;
    final wordWidgets = <Widget>[];
    final lineChildren = <MushafLineChild>[];
    int? highlightStartIndex;
    int? highlightEndIndex;

    final EdgeInsets wordPadding = EdgeInsets.symmetric(
      horizontal: shouldJustify ? 1.0 : 3.5,
      vertical: 1.0,
    );

    final TextStyle defaultWordStyle = TextStyle(
      fontFamily: wordFontFamily,
      fontSize: fontSize,
      color: colors.text,
      height: 1.25,
    );

    if (isPageIdle) {
      // ULTRA-FAST ZERO-ALLOCATION IDLE PATH:
      int cachedSurah = -1;
      int cachedAyah = -1;
      List<String>? cachedWords;

      for (int i = 0; i < parsedWords.length; i++) {
        final ref = parsedWords[i];
        final surah = ref.surah;
        final ayah = ref.ayah;
        final wordIndex1 = ref.wordIndex1;
        final wordIndex0 = ref.wordIndex0;

        if (surah != cachedSurah || ayah != cachedAyah) {
          cachedSurah = surah;
          cachedAyah = ayah;
          final ayahKey = '$surah:$ayah';
          var words = verseWordsMemoryCache[ayahKey];
          if (words == null) {
            final v = controller.repository.getVerse(surah, ayah);
            if (v != null) {
              words = v.uthmaniWords;
              verseWordsMemoryCache[ayahKey] = words;
            }
          }
          cachedWords = words;
        }

        final words = cachedWords;
        if (words == null || wordIndex0 >= words.length) continue;

        final wordText = words[wordIndex0];
        wordWidgets.add(
          Padding(
            padding: wordPadding,
            child: Text(
              wordText,
              textDirection: TextDirection.rtl,
              textScaler: TextScaler.noScaling,
              style: defaultWordStyle,
            ),
          ),
        );
        lineChildren.add(
          MushafLineChild.word(
            surah: surah,
            ayah: ayah,
            wordIndex0: wordIndex0,
            wordText: wordText,
          ),
        );

        final bool isLastWordOfAyah = wordIndex1 == words.length ||
            (i < parsedWords.length - 1 && parsedWords[i + 1].ayah != ayah);
        if (isLastWordOfAyah) {
          wordWidgets.add(
            MushafAyahMarker(
              surah: surah,
              ayah: ayah,
              fontSize: fontSize,
              isAyahActive: false,
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
          lineChildren.add(
            MushafLineChild.marker(
              surah: surah,
              ayah: ayah,
            ),
          );
        }
      }
    } else {
      List<String>? cachedWords;
      bool cachedIsAyahActive = false;
      bool cachedIsCompleted = false;
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
          final ayahKey = '$surah:$ayah';
          var words = verseWordsMemoryCache[ayahKey];
          if (words == null) {
            final v = controller.repository.getVerse(surah, ayah);
            if (v != null) {
              words = v.uthmaniWords;
              verseWordsMemoryCache[ayahKey] = words;
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
          cachedTargetIndex = cachedIsAyahActive
              ? VerseRow.getTargetWordIndex(
                  surah: surah,
                  ayah: ayah,
                  words: cachedWords ?? const [],
                  controller: controller,
                  app: app,
                  isRecording: isRecording,
                  isActive: true,
                )
              : -1;
          cachedIsCompleted =
              controller.completedAyahsFor(surah).contains(ayah);
        }

        final words = cachedWords;
        if (words == null || wordIndex0 >= words.length) continue;

        final wordText = words[wordIndex0];
        final bool isAyahActive = cachedIsAyahActive;
        final int targetIndex = cachedTargetIndex;
        final bool isWordActive = (targetIndex == wordIndex0);

        final Color textColor;
        final bool hasSessionHighlights = controller.globalRevision.value > 0;
        if (isRecording || cachedIsAyahActive || app.isBlurMode || cachedIsCompleted || hasSessionHighlights) {
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

        // Active word focus pill: tuned for optimal contrast against the Ayah ribbon
        final BoxDecoration? wordDecoration = isWordActive
            ? BoxDecoration(
                color: colors.wordHighlight.withValues(
                  alpha: isDark ? 0.14 : 0.18,
                ),
                borderRadius: BorderRadius.circular(6),
              )
            : null;

        final int wordWidgetIndex = wordWidgets.length;
        if (isAyahActive) {
          highlightStartIndex ??= wordWidgetIndex;
          highlightEndIndex = wordWidgetIndex;
        }

        final wordTextWidget = Text(
          wordText,
          textDirection: TextDirection.rtl,
          textScaler: TextScaler.noScaling,
          style: textColor == colors.text
              ? defaultWordStyle
              : defaultWordStyle.copyWith(color: textColor),
        );

        wordWidgets.add(
          wordDecoration == null
              ? Padding(padding: wordPadding, child: wordTextWidget)
              : Container(
                  padding: wordPadding,
                  decoration: wordDecoration,
                  child: wordTextWidget,
                ),
        );
        lineChildren.add(
          MushafLineChild.word(
            surah: surah,
            ayah: ayah,
            wordIndex0: wordIndex0,
            wordText: wordText,
          ),
        );

        // Ayah number marker at the end of the Ayah
        final bool isLastWordOfAyah = wordIndex1 == words.length ||
            (i < parsedWords.length - 1 && parsedWords[i + 1].ayah != ayah);
        if (isLastWordOfAyah) {
          final int markerWidgetIndex = wordWidgets.length;
          if (isAyahActive) {
            highlightStartIndex ??= markerWidgetIndex;
            highlightEndIndex = markerWidgetIndex;
          }
          wordWidgets.add(
            MushafAyahMarker(
              surah: surah,
              ayah: ayah,
              fontSize: fontSize,
              isAyahActive: isAyahActive,
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
          lineChildren.add(
            MushafLineChild.marker(
              surah: surah,
              ayah: ayah,
            ),
          );
        }
      }
    }

    void handleLineTap(Offset localPosition) {
      if (isAutoScrolling) return;
      if (lineChildren.isEmpty) return;

      final renderFlex =
          lineKey.currentContext?.findRenderObject() as RenderMushafHighlightFlex?;
      final int targetIndex;
      if (renderFlex != null && renderFlex.hasSize) {
        targetIndex = renderFlex.findClosestChildIndex(localPosition.dx);
      } else {
        final double ratio =
            (1.0 - (localPosition.dx / lineWidth)).clamp(0.0, 1.0);
        targetIndex = (ratio * lineChildren.length)
            .floor()
            .clamp(0, lineChildren.length - 1);
      }

      if (targetIndex >= 0 && targetIndex < lineChildren.length) {
        final child = lineChildren[targetIndex];
        if (child.isMarker) {
          app.markMushafAudioAyahClicked();
          VerseRow.toggleAyahAudio(
            surah: child.surah,
            ayah: child.ayah,
            controller: controller,
            isRecording: isRecording,
            onTap: onStateChangeRequested,
          );
        } else {
          VerseRow.handleWordTap(
            context: context,
            surah: child.surah,
            ayah: child.ayah,
            wordIndex: child.wordIndex0,
            wordText: child.wordText,
            controller: controller,
            isAutoScrolling: isAutoScrolling,
            onAyahTap: onStateChangeRequested,
          );
        }
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
            minWidth: shouldJustify ? lineWidth : 0.0,
            maxHeight: lineHeight,
          ),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (details) => handleLineTap(details.localPosition),
            child: MushafHighlightRow(
              key: lineKey,
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
}
