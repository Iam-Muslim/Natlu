import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:recite_quran/recite_quran.dart';

import '../../../../state/app_state.dart';
import '../../helpers/verse_span_builder.dart';
import '../../verse_row.dart';
import '../classes/line.dart';
import '../classes/word.dart';
import 'ayah_marker.dart';
import 'highlight_row.dart';

/// ============================================================================
/// CRITICAL LAYOUT COMPONENT: [LineWidget]
/// ============================================================================
/// ARCHITECTURAL RULES & INVARIANTS — DO NOT ALTER WITHOUT READING:
///
/// 1. SURAH BANNER & BISMILLAH INTEGRATION:
///    - In [_buildSurahHeader], Surah name is strictly on the right (RTL start)
///      with only one "سُورَةُ ..." prefix.
///    - Bismillah is embedded directly inside the banner on the left (RTL end)
///      using authentic HafsSmart font & PUA unicode glyphs, matching `colors.text`.
///    - Surah 9 (At-Tawbah) automatically omits Bismillah per Islamic Quranic law.
///    - Redundant [BasmalaLine] returns [SizedBox.shrink] so Bismillah is never repeated.
///
/// 2. JUSTIFICATION & LINE-ABOVE-BANNER RULE:
///    - DO NOT reintroduce `!nextLineHasSurahHeader` in [shouldJustify]!
///    - Lines above a Surah banner are standard Quranic lines and MUST justify
///      normally across the page. Forcing them to center with padding causes them to
///      overflow and shrink by 35%, making them look unnaturally tiny!
///    - Centering is strictly reserved for very short lines (`wordCount <= 3`) with
///      gentle margins (`3.0px`) that never trigger FittedBox scale down.
///
/// 3. AYAH MARKER 100% FIXED SIZE (17.0px):
///    - [measureLineTextWidth] calculates the exact pixel width of the text using [TextPainter].
///    - `lineScaleFactor` is computed and passed to [MushafAyahMarker].
///    - The marker applies an exact inverse counter-scale (`1 / scaleFactor`) so that
///      FittedBox scaling is canceled out, locking the marker at 17.0px on every line!
///
/// 4. DYNAMIC FONT SIZING:
///    - Short lines (<= 3 words): capped at 18.0px (NEVER balloon).
///    - Medium lines (4 to 7 words): capped at 18.6px.
///    - Dense lines (>= 8 words): full fontSize with 0.0px margins so smaller lines
///      become dynamically bigger without enlarging medium/short lines.
/// ============================================================================
class LineWidget extends StatelessWidget {
  final Line line;
  final Line? nextLine;
  final int pageNumber;
  final int lineIndex;
  final double? lineWidth;
  final double? lineHeight;
  final double fontSize;
  final String wordFontFamily;
  final ThemeColors colors;
  final AppState app;
  final HighlightingController controller;
  final bool isRecording;
  final bool isAutoScrolling;
  final VoidCallback? onAyahSelected;

  const LineWidget({
    super.key,
    required this.line,
    this.nextLine,
    required this.pageNumber,
    required this.lineIndex,
    this.lineWidth,
    this.lineHeight,
    required this.fontSize,
    this.wordFontFamily = 'HafsSmart',
    required this.colors,
    required this.app,
    required this.controller,
    this.isRecording = false,
    required this.isAutoScrolling,
    this.onAyahSelected,
  });

  /// ============================================================================
  /// ARCHITECTURAL INVARIANT: JUSTIFICATION POLICY
  /// ============================================================================
  /// True for all lines on standard pages (3..604) so text stretches seamlessly edge-to-edge.
  ///
  /// CRITICAL WARNING TO ANY AI AGENT OR DEVELOPER:
  /// NEVER, UNDER ANY CIRCUMSTANCES, ADD `!nextLineHasSurahHeader` TO THIS GETTER!
  /// Doing so treats the standard Quranic line immediately preceding a Surah header as
  /// "un-justified", which injects 8.0px horizontal margins between words, causing the
  /// total line width to exceed the screen width by >100px. FittedBox then shrinks that line
  /// down to ~65% of its normal size, making it look unnaturally tiny and broken!
  ///
  /// The ONLY lines that should not justify are:
  /// - Pages 1 and 2 (Al-Fatiha and Al-Baqarah opening).
  /// - Line 15 (bottom line) on page 600..604 (Quran concluding pages with short final surahs).
  /// ============================================================================
  bool get shouldJustify {
    return pageNumber > 2 && (lineIndex != 14 || pageNumber <= 599);
  }

  @override
  Widget build(BuildContext context) {
    if (line is SurahHeaderLine) {
      return _buildSurahHeader(context, line as SurahHeaderLine);
    }

    if (line is BasmalaLine) {
      return _buildBasmala(context, line as BasmalaLine);
    }

    if (line is TextLine) {
      return _buildTextLine(context, line as TextLine);
    }

    return const SizedBox.shrink();
  }

  /// ============================================================================
  /// ARCHITECTURAL INVARIANT: SURAH HEADER BANNER & EMBEDDED BISMILLAH
  /// ============================================================================
  /// 1. Surah Name:
  ///    - Positioned strictly on the RIGHT (RTL start).
  ///    - Uses Cairo bold typography.
  ///    - Prefix "سُورَةُ ..." is formatted once without duplicate prefixes.
  ///
  /// 2. Embedded Bismillah:
  ///    - Positioned strictly on the LEFT (RTL end) inside the banner.
  ///    - Uses authentic HafsSmart font (`wordFontFamily`) and authentic PUA ligatures:
  ///      `'‏ ‏‏ ‏‏‏‏ ‏‏‏‏‏‏'`
  ///    - Color matches `colors.text` (solid black in light mode, crisp white in dark mode).
  ///    - Surah 9 (At-Tawbah) strictly OMITS Bismillah per Quranic law.
  ///
  /// DO NOT move Bismillah out of the banner or replace the Hafs font glyphs!
  /// ============================================================================
  Widget _buildSurahHeader(BuildContext context, SurahHeaderLine header) {
    // Ensure only ONE "سورة" label appears on the right
    String displayName = header.surahName.trim();
    if (!displayName.startsWith('سورة') && !displayName.startsWith('سُورَة')) {
      displayName = 'سُورَةُ $displayName';
    }

    return SizedBox(
      width: lineWidth ?? double.infinity,
      height: (lineHeight != null ? (lineHeight! * 0.88) : null),
      child: Center(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            HapticFeedback.lightImpact();
            VerseRow.selectAyah(
              surah: header.surahNumber,
              ayah: 1,
              controller: controller,
              onTap: onAyahSelected,
            );
          },
          child: Container(
            width: double.infinity,
            margin: const EdgeInsets.symmetric(vertical: 1.0, horizontal: 2.0),
            padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 2.5),
            decoration: BoxDecoration(
              color: colors.surfaceHigh,
              borderRadius: BorderRadius.circular(8.0),
              border: Border.all(
                color: colors.gold.withValues(alpha: 0.65),
                width: 1.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: app.isDarkMode ? 0.30 : 0.05),
                  blurRadius: 4.0,
                  offset: const Offset(0, 1.5),
                ),
              ],
            ),
            child: Row(
              textDirection: TextDirection.rtl,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Right: Surah Name
                Flexible(
                  flex: 0,
                  child: Text(
                    displayName,
                    textDirection: TextDirection.rtl,
                    style: TextStyle(
                      fontFamily: 'cairo',
                      fontSize: 13.5,
                      fontWeight: FontWeight.bold,
                      color: colors.text,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Left: Bismillah using authentic HafsSmart font & PUA unicodes, colored as label color (black in light mode)
                if (header.surahNumber != 9)
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '‏ ‏‏ ‏‏‏‏ ‏‏‏‏‏‏',
                        textDirection: TextDirection.rtl,
                        textScaler: TextScaler.noScaling,
                        style: TextStyle(
                          fontFamily: wordFontFamily,
                          fontSize: 15.0,
                          color: colors.text,
                          height: 1.05,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// ============================================================================
  /// ARCHITECTURAL INVARIANT: STANDALONE BASMALA OMISSION
  /// ============================================================================
  /// Redundant because Bismillah is now beautifully embedded directly inside
  /// [_buildSurahHeader] on the left. Must always return SizedBox.shrink().
  /// ============================================================================
  Widget _buildBasmala(BuildContext context, BasmalaLine basmala) {
    return const SizedBox.shrink();
  }

  /// ============================================================================
  /// ARCHITECTURAL INVARIANT: TEXT LINE RENDERING & JUSTIFICATION
  /// ============================================================================
  Widget _buildTextLine(BuildContext context, TextLine textLine) {
    final words = textLine.words;
    if (words.isEmpty) return const SizedBox.shrink();

    final int wordCount = words.length;

    // --------------------------------------------------------------------------
    // DYNAMIC CALIBRATED FONT SIZE (ANTI-BALLOONING POLICY):
    // --------------------------------------------------------------------------
    // - Short lines (<= 3 words): capped at 18.0px so they NEVER balloon or get too big.
    // - Medium lines (4 to 7 words): capped at 18.6px so they stay comfortable.
    // - Dense lines (>= 8 words): receive the full available font (up to 19.0px)
    //   with 0.0px margin so dense lines become dynamically bigger without
    //   enlarging medium/short lines!
    // --------------------------------------------------------------------------
    final double effectiveFontSize;
    if (wordCount <= 3) {
      effectiveFontSize = fontSize.clamp(16.5, 18.0);
    } else if (wordCount <= 7) {
      effectiveFontSize = fontSize.clamp(17.0, 18.6);
    } else {
      effectiveFontSize = fontSize;
    }

    // --------------------------------------------------------------------------
    // CENTERING VS JUSTIFICATION:
    // --------------------------------------------------------------------------
    // Only very short lines (<= 3 words) are centered so words are not thrown across the screen.
    // Standard lines justify edge-to-edge across the page width.
    // --------------------------------------------------------------------------
    final bool isLineCentered = !shouldJustify || wordCount <= 3;
    final double marginHorizontal = isLineCentered
        ? (wordCount <= 3 ? 3.0 : 1.5)
        : (wordCount <= 5 ? 2.5 : (wordCount <= 7 ? 1.0 : 0.0));

    // --------------------------------------------------------------------------
    // CRITICAL: EXACT SCALE FACTOR CALCULATION FOR AYAH MARKER INVARIANCE
    // --------------------------------------------------------------------------
    // We measure the exact natural width of this line's words via TextPainter.
    // Total natural width = text width + markers (21px each).
    // If totalNaturalWidth > effectiveLineWidth, FittedBox will scale the line down by:
    // lineScaleFactor = effectiveLineWidth / totalNaturalWidth.
    // We pass this exact lineScaleFactor to MushafAyahMarker so it can apply:
    // Transform.scale(scale: 1 / lineScaleFactor), locking the marker at 17.0px!
    // --------------------------------------------------------------------------
    final int markerCount = words.where((w) => w.isAyahEnd).length;
    final double textNaturalWidth = measureLineTextWidth(words, effectiveFontSize, wordFontFamily);
    final double markerNaturalWidth = markerCount * 21.0;
    final double totalNaturalWidth = textNaturalWidth + markerNaturalWidth;
    final double effectiveLineWidth = lineWidth ?? 360.0;
    final double lineScaleFactor = (totalNaturalWidth > effectiveLineWidth)
        ? (effectiveLineWidth / totalNaturalWidth).clamp(0.5, 1.0)
        : 1.0;

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

    for (int i = 0; i < words.length; i++) {
      final word = words[i];
      final int surah = word.getSurahNumber() ?? 1;
      final int ayah = word.getVerseNumber() ?? 1;
      final int wordIndex0 = word.getWordIndex0();

      if (surah != lastCachedSurah || ayah != lastCachedAyah) {
        lastCachedSurah = surah;
        lastCachedAyah = ayah;

        final v = controller.repository.getVerse(surah, ayah);
        cachedWords = v?.uthmaniWords;

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
        cachedIsCompleted = controller.completedAyahsFor(surah).contains(ayah);
      }

      final bool isWordActive = (cachedTargetIndex == wordIndex0);

      // Color resolution from ASR and reading sessions
      final Color wordColor;
      final bool hasSessionHighlights = controller.globalRevision.value > 0;
      if (isRecording ||
          cachedIsAyahActive ||
          app.isBlurMode ||
          cachedIsCompleted ||
          hasSessionHighlights) {
        wordColor = VerseSpanBuilder.resolveWordDisplayColor(
          ayah: ayah,
          wordIndex: wordIndex0,
          controller: controller,
          app: app,
          colors: colors,
          isAutoScrolling: isAutoScrolling,
          surah: surah,
        );
      } else {
        wordColor = colors.text;
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

      final Widget wordTextWidget = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (isAutoScrolling) return;
          VerseRow.handleWordTap(
            context: context,
            surah: surah,
            ayah: ayah,
            wordIndex: wordIndex0,
            wordText: word.word,
            controller: controller,
            isAutoScrolling: isAutoScrolling,
            onAyahTap: onAyahSelected,
            playWordDirectly: true,
          );
        },
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: marginHorizontal, vertical: 1.0),
          decoration: wordDecoration,
          child: Text(
            word.text,
            textDirection: TextDirection.rtl,
            textScaler: TextScaler.noScaling,
            style: TextStyle(
              fontFamily: wordFontFamily,
              fontSize: effectiveFontSize,
              color: wordColor,
              height: 1.25,
            ),
          ),
        ),
      );

      wordWidgets.add(wordTextWidget);

      // Append interactive squircle Ayah Marker if this word is the end of an Ayah
      if (word.isAyahEnd) {
        final int markerWidgetIndex = wordWidgets.length;
        if (cachedIsAyahActive) {
          highlightStartIndex ??= markerWidgetIndex;
          highlightEndIndex = markerWidgetIndex;
        }

        // ----------------------------------------------------------------------
        // CRITICAL: AYAH MARKER WITH INVERSE COUNTER-SCALE
        // ----------------------------------------------------------------------
        // We pass `scaleFactor: lineScaleFactor` so that the marker applies:
        // Transform.scale(scale: 1 / scaleFactor).
        // DO NOT REMOVE scaleFactor OR ATTEMPT TO RESIZE THE MARKER DYNAMICALLY.
        // Doing so breaks physical size constancy across phone screens!
        // ----------------------------------------------------------------------
        wordWidgets.add(
          MushafAyahMarker(
            surah: surah,
            ayah: ayah,
            fontSize: effectiveFontSize,
            scaleFactor: lineScaleFactor,
            isAyahActive: cachedIsAyahActive,
            colors: colors,
            app: app,
            controller: controller,
            isRecording: isRecording,
            isAutoScrolling: isAutoScrolling,
            onAudioToggled: onAyahSelected,
          ),
        );
      }
    }

    final row = MushafHighlightRow(
      mainAxisAlignment: isLineCentered
          ? MainAxisAlignment.center
          : MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: isLineCentered ? MainAxisSize.min : MainAxisSize.max,
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

    // --------------------------------------------------------------------------
    // CRITICAL: SEAMLESS INTERACTION & JUSTIFICATION ENGINE
    // --------------------------------------------------------------------------
    // 1. Interactive Background Stack:
    //    The Stack has a full-size Positioned.fill background that catches taps on
    //    the empty spaces between words, above/below text, and between lines!
    //    Taps on specific words or markers hit the foreground directly.
    // 2. FittedBox & ConstrainedBox:
    //    Stretches standard lines edge-to-edge across lineWidth.
    // --------------------------------------------------------------------------
    return SizedBox(
      width: lineWidth ?? double.infinity,
      height: lineHeight,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Background hit area for empty spaces between words and between lines
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (details) {
                if (isAutoScrolling) return;
                _handleLineTap(details.localPosition.dx, effectiveLineWidth, words);
              },
            ),
          ),
          // Foreground text and markers
          Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.center,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minWidth: isLineCentered ? 0.0 : (lineWidth ?? 0.0),
                ),
                child: row,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Handles tapping on spaces between words or spaces between lines of an Ayah.
  /// Selects the Ayah corresponding to the tap position with haptic feedback.
  void _handleLineTap(
    double tapX,
    double totalWidth,
    List<Word> words,
  ) {
    if (words.isEmpty) return;

    final firstSurah = words.first.getSurahNumber() ?? 1;
    final firstAyah = words.first.getVerseNumber() ?? 1;
    bool allSameAyah = true;
    for (int i = 1; i < words.length; i++) {
      if (words[i].getSurahNumber() != firstSurah ||
          words[i].getVerseNumber() != firstAyah) {
        allSameAyah = false;
        break;
      }
    }

    final int targetSurah;
    final int targetAyah;

    if (allSameAyah) {
      targetSurah = firstSurah;
      targetAyah = firstAyah;
    } else {
      // In RTL layout: tapX == totalWidth is right (words[0]), tapX == 0 is left (words.last)
      final double clampedWidth = totalWidth > 0 ? totalWidth : 360.0;
      final double ratioFromRight = ((clampedWidth - tapX) / clampedWidth).clamp(0.0, 1.0);
      final int wordIndex = (ratioFromRight * words.length).floor().clamp(0, words.length - 1);
      final selectedWord = words[wordIndex];
      targetSurah = selectedWord.getSurahNumber() ?? firstSurah;
      targetAyah = selectedWord.getVerseNumber() ?? firstAyah;
    }

    HapticFeedback.lightImpact();
    VerseRow.selectAyah(
      surah: targetSurah,
      ayah: targetAyah,
      controller: controller,
      onTap: onAyahSelected,
    );
  }

  /// ============================================================================
  /// ARCHITECTURAL INVARIANT: EXACT LINE TEXT MEASUREMENT (WITH ZERO-GPU CACHING)
  /// ============================================================================
  /// Uses [TextPainter] with identical typography to compute the unscaled natural
  /// width of the line's words.
  /// Results are cached statically by line content & font size so layout is
  /// computed exactly once per line, delivering blazing-fast 120 FPS performance!
  /// ============================================================================
  static final Map<int, double> _lineWidthCache = {};

  static double measureLineTextWidth(
    List<Word> words,
    double fontSize,
    String fontFamily,
  ) {
    if (words.isEmpty) return 0.0;

    final int cacheKey = Object.hash(
      words.length,
      words.first.text,
      words.last.text,
      (fontSize * 10).round(),
      fontFamily,
    );
    final cached = _lineWidthCache[cacheKey];
    if (cached != null) return cached;

    final StringBuffer sb = StringBuffer();
    for (int i = 0; i < words.length; i++) {
      if (i > 0) sb.write(' ');
      sb.write(words[i].text);
    }
    final TextPainter tp = TextPainter(
      text: TextSpan(
        text: sb.toString(),
        style: TextStyle(
          fontFamily: fontFamily,
          fontSize: fontSize,
          height: 1.25,
        ),
      ),
      textDirection: TextDirection.rtl,
    )..layout();
    final double width = tp.width;
    tp.dispose();
    _lineWidthCache[cacheKey] = width;
    return width;
  }
}
