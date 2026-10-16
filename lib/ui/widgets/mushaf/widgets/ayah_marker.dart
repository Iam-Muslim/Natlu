import 'package:flutter/material.dart';
import 'package:recite_quran/recite_quran.dart';

import '../../../../state/app_state.dart';
import '../../verse_row.dart';

/// ============================================================================
/// CRITICAL LAYOUT COMPONENT: [MushafAyahMarker]
/// ============================================================================
/// ARCHITECTURAL RULES & INVARIANTS — DO NOT ALTER WITHOUT READING:
///
/// 1. FIXED PHYSICAL SCREEN SIZE (17.0 x 17.0):
///    - In Quran Mushaf, every Ayah marker MUST maintain an identical physical
///      size across every line on the screen.
///    - Because parent lines use `FittedBox(fit: BoxFit.scaleDown)` to ensure dense
///      text lines fit within the screen width, `MushafAyahMarker` receives
///      `scaleFactor` and applies an exact inverse [Transform.scale] (`counterScale = 1 / scaleFactor`).
///    - Formula: On-Screen Size = boxSize * (1 / scaleFactor) * scaleFactor = EXACTLY boxSize.
///    - DO NOT remove `scaleFactor` or `counterScale`, otherwise markers on dense lines
///      will shrink to ~12px while short lines stay at ~17px, causing an eye-straining
///      fluctuation across lines.
///
/// 2. HARMONIOUS DIGIT TYPOGRAPHY:
///    - 1-digit ayahs (1..9):   fontSize: 8.5,  w600 (NEVER use w700 or >9.0px, otherwise single digits balloon).
///    - 2-digit ayahs (10..99):  fontSize: 8.0,  w600.
///    - 3-digit ayahs (100..286): fontSize: 7.5, w600.
///    - This guarantees identical optical weight and height across all verses.
///
/// 3. INTERACTION & AUDIO:
///    - Tapping toggles recitation playback for that specific Ayah.
///    - When playing/buffering, displays a stop icon or mini circular progress spinner.
/// ============================================================================
class MushafAyahMarker extends StatelessWidget {
  final int surah;
  final int ayah;
  final double fontSize;
  final double scaleFactor;
  final bool isAyahActive;
  final ThemeColors colors;
  final AppState app;
  final HighlightingController controller;
  final bool isRecording;
  final bool isAutoScrolling;
  final String? ayahMarkerFontFamily;
  final Color? ayahMarkerBorderColor;
  final Color? ayahMarkerTextColor;
  final double ayahMarkerBorderWidth;
  final bool showAyahMarkerCircle;
  final VoidCallback? onAudioToggled;

  const MushafAyahMarker({
    super.key,
    required this.surah,
    required this.ayah,
    required this.fontSize,
    this.scaleFactor = 1.0,
    required this.isAyahActive,
    required this.colors,
    required this.app,
    required this.controller,
    required this.isRecording,
    required this.isAutoScrolling,
    this.ayahMarkerFontFamily,
    this.ayahMarkerBorderColor,
    this.ayahMarkerTextColor,
    this.ayahMarkerBorderWidth = 1.2,
    this.showAyahMarkerCircle = true,
    this.onAudioToggled,
  });

  @override
  Widget build(BuildContext context) {
    final bool isDark = app.isDarkMode;
    final bool isPlaying = VerseRow.isAyahAudioPlaying(surah, ayah);
    final bool isBuffering = VerseRow.isAyahAudioBuffering(surah, ayah);

    // ==========================================================================
    // ARCHITECTURAL INVARIANT: EXACT 17.0px PHYSICAL SCREEN SIZE
    // ==========================================================================
    // - boxSize is strictly 17.0px.
    // - counterScale = 1.0 / scaleFactor cancels any scale-down applied by the
    //   parent line's FittedBox.
    // - On-Screen Size = boxSize * (1 / scaleFactor) * scaleFactor = EXACTLY 17.0px.
    //
    // CRITICAL WARNING:
    // DO NOT REMOVE counterScale!
    // DO NOT make boxSize dynamic or responsive to line length!
    // Every Ayah marker across the entire Quran must look identical in size.
    // ==========================================================================
    const double boxSize = 17.0;
    final double counterScale = scaleFactor > 0 ? (1.0 / scaleFactor) : 1.0;

    // ==========================================================================
    // HARMONIOUS DIGIT TYPOGRAPHY (ANTI-BALLOONING POLICY):
    // ==========================================================================
    // - 1-digit ayahs (1..9):    fontSize: 8.5, w600.
    //   (DO NOT use >8.5 or w700, otherwise single digits balloon and look huge!)
    // - 2-digit ayahs (10..99):   fontSize: 8.0, w600.
    // - 3-digit ayahs (100..286): fontSize: 7.5, w600.
    // ==========================================================================
    final double numFontSize;
    final double letterSpacing;
    if (ayah < 10) {
      numFontSize = 8.5;
      letterSpacing = 0.0;
    } else if (ayah < 100) {
      numFontSize = 8.0;
      letterSpacing = 0.0;
    } else {
      numFontSize = 7.5;
      letterSpacing = -0.3;
    }

    final Color boxBgColor;
    final Color boxBorderColor;
    final Color numTextColor;

    if (isPlaying || isBuffering) {
      if (isDark) {
        boxBgColor = colors.primary.withValues(alpha: 0.20);
        boxBorderColor = colors.primary.withValues(alpha: 0.55);
        numTextColor = colors.primary;
      } else {
        boxBgColor = colors.primary.withValues(alpha: 0.10);
        boxBorderColor = colors.primary.withValues(alpha: 0.40);
        numTextColor = colors.primary;
      }
    } else if (isAyahActive) {
      boxBgColor = isDark
          ? Colors.white.withValues(alpha: 0.12)
          : const Color(0xFF64748B).withValues(alpha: 0.10);
      boxBorderColor = isDark
          ? Colors.white.withValues(alpha: 0.30)
          : const Color(0xFF64748B).withValues(alpha: 0.28);
      numTextColor = isDark ? Colors.white : const Color(0xFF0F172A);
    } else {
      boxBgColor = isDark
          ? Colors.white.withValues(alpha: 0.06)
          : const Color(0xFF64748B).withValues(alpha: 0.05);
      boxBorderColor = isDark
          ? Colors.white.withValues(alpha: 0.18)
          : const Color(0xFF64748B).withValues(alpha: 0.16);
      numTextColor = isDark
          ? const Color(0xFFCBD5E1)
          : const Color(0xFF475569);
    }

    final Color effectiveBorder = (isPlaying || isBuffering)
        ? boxBorderColor
        : (ayahMarkerBorderColor ?? boxBorderColor);
    final Color effectiveText = (isPlaying || isBuffering)
        ? numTextColor
        : (ayahMarkerTextColor ?? numTextColor);

    final String markerFont = ayahMarkerFontFamily ?? 'cairo';

    final boxDecoration = showAyahMarkerCircle
        ? BoxDecoration(
            color: (isPlaying || isBuffering)
                ? boxBgColor
                : (ayahMarkerBorderColor != null ? null : boxBgColor),
            borderRadius: BorderRadius.circular(boxSize * 0.26),
            border: Border.all(
              color: effectiveBorder,
              width: 0.8,
            ),
          )
        : null;

    final staticContent = Text(
      VerseRow.toArabicDigits(ayah),
      key: ValueKey('ayah_$ayah'),
      textDirection: TextDirection.rtl,
      textScaler: TextScaler.noScaling,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontFamily: markerFont,
        fontSize: numFontSize,
        letterSpacing: letterSpacing,
        color: effectiveText,
        fontWeight: FontWeight.w600,
        height: 1.0,
      ),
    );

    final Widget mainWidget;
    if (!isPlaying && !isBuffering) {
      mainWidget = Semantics(
        button: true,
        label: 'تشغيل التلاوة',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            if (isAutoScrolling) return;
            app.markMushafAudioAyahClicked();
            VerseRow.toggleAyahAudio(
              surah: surah,
              ayah: ayah,
              controller: controller,
              isRecording: isRecording,
              onTap: onAudioToggled,
            );
          },
          child: Container(
            width: showAyahMarkerCircle ? boxSize : null,
            height: showAyahMarkerCircle ? boxSize : null,
            margin: const EdgeInsets.symmetric(horizontal: 2.0),
            alignment: Alignment.center,
            decoration: boxDecoration,
            child: staticContent,
          ),
        ),
      );
    } else {
      mainWidget = Semantics(
        button: true,
        label: isPlaying ? 'إيقاف مؤقت' : 'تشغيل التلاوة',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            if (isAutoScrolling) return;
            app.markMushafAudioAyahClicked();
            VerseRow.toggleAyahAudio(
              surah: surah,
              ayah: ayah,
              controller: controller,
              isRecording: isRecording,
              onTap: onAudioToggled,
            );
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            width: showAyahMarkerCircle ? boxSize : null,
            height: showAyahMarkerCircle ? boxSize : null,
            margin: const EdgeInsets.symmetric(horizontal: 2.0),
            alignment: Alignment.center,
            decoration: boxDecoration,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 150),
              transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                child: ScaleTransition(scale: anim, child: child),
              ),
              child: isBuffering
                  ? SizedBox(
                      key: const ValueKey('buffering'),
                      width: (boxSize * 0.48).clamp(8.5, 11.0),
                      height: (boxSize * 0.48).clamp(8.5, 11.0),
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        valueColor: AlwaysStoppedAnimation<Color>(colors.primary),
                      ),
                    )
                  : isPlaying
                      ? Icon(
                          key: const ValueKey('playing'),
                          Icons.stop_rounded,
                          size: (boxSize * 0.54).clamp(10.0, 13.5),
                          color: colors.primary,
                        )
                      : staticContent,
            ),
          ),
        ),
      );
    }

    // --------------------------------------------------------------------------
    // CRITICAL: COUNTER-SCALE TO CANCEL OUT PARENT'S FITTEDBOX SCALE
    // --------------------------------------------------------------------------
    // If the parent line was scaled down by `scaleFactor` (e.g. 0.85),
    // we multiply by `1 / 0.85 = 1.176`, so the rendered screen size is:
    // (17.0 * 1.176) * 0.85 = EXACTLY 17.0px!
    // DO NOT REMOVE THIS TRANSFORM!
    // --------------------------------------------------------------------------
    if (counterScale != 1.0) {
      return Transform.scale(
        scale: counterScale,
        alignment: Alignment.center,
        child: mainWidget,
      );
    }
    return mainWidget;
  }
}
