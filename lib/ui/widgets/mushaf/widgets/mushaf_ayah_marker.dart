import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:recite_quran/recite_quran.dart';

import '../../../../state/app_state.dart';
import '../../verse_row.dart';

/// Standard Mushaf Ayah Marker:
/// - Uniform 1:1 squircle dimensions across ALL ayahs (never stretching into rectangles).
/// - Calibrated standard typographic scale: 1, 2, and 3 digits maintain harmonious optical size and weight.
/// - Optically centered vertically and horizontally inside the box.
/// - Eye-comfortable neutral scheme matching the Ayah highlight ribbon (zero distraction).
/// - Instant audio play/pause and selection on tap.
class MushafAyahMarker extends StatelessWidget {
  final int surah;
  final int ayah;
  final double fontSize;
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
    final bool isPlaying =
        isAyahActive && VerseRow.isAyahAudioPlaying(surah, ayah);
    final bool isBuffering =
        isAyahActive && VerseRow.isAyahAudioBuffering(surah, ayah);

    // Standard uniform 1:1 box size across all ayahs on the page (matches line height proportions)
    final double maxBox = math.max(14.0, fontSize * 1.02);
    final double boxSize =
        (fontSize * 1.02).clamp(math.min(16.0, maxBox), 26.5);

    // Calibrated typography so 1, 2, and 3 digits maintain standard optical height and weight
    final double numFontSize;
    final double letterSpacing;
    if (ayah < 10) {
      numFontSize = (boxSize * 0.52).clamp(8.0, 13.5);
      letterSpacing = 0.0;
    } else if (ayah < 100) {
      numFontSize = (boxSize * 0.48).clamp(7.5, 12.2);
      letterSpacing = -0.2;
    } else {
      numFontSize = (boxSize * 0.43).clamp(7.0, 11.0);
      letterSpacing = -0.4;
    }

    // Color scheme: Grey/neutral palette matching the highlighted Ayah ribbon for eye comfort and zero distraction
    final Color boxBgColor;
    final Color boxBorderColor;
    final Color numTextColor;

    if (isPlaying || isBuffering) {
      if (isDark) {
        boxBgColor = colors.primary.withValues(alpha: 0.22);
        boxBorderColor = colors.primary.withValues(alpha: 0.60);
        numTextColor = colors.primary;
      } else {
        boxBgColor = colors.primary.withValues(alpha: 0.12);
        boxBorderColor = colors.primary.withValues(alpha: 0.45);
        numTextColor = colors.primary;
      }
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

    final Color effectiveBorder = (isPlaying || isBuffering)
        ? boxBorderColor
        : (ayahMarkerBorderColor ?? boxBorderColor);
    final Color effectiveText = (isPlaying || isBuffering)
        ? numTextColor
        : (ayahMarkerTextColor ?? numTextColor);

    final String markerFont = ayahMarkerFontFamily ?? 'cairo';
    final bool isHafs = markerFont.toLowerCase().contains('hafs');
    final double verticalOffset = isHafs ? -2.0 : -0.4;

    final boxDecoration = showAyahMarkerCircle
        ? BoxDecoration(
            color: (isPlaying || isBuffering)
                ? boxBgColor
                : (ayahMarkerBorderColor != null ? null : boxBgColor),
            borderRadius: BorderRadius.circular(boxSize * 0.28), // Sleek flat squircle
            border: Border.all(
              color: effectiveBorder,
              width: ayahMarkerBorderWidth > 0 ? ayahMarkerBorderWidth : 1.0,
            ),
          )
        : null;

    final staticContent = Transform.translate(
      key: ValueKey('ayah_$ayah'),
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
    );

    // Fast static path for idle markers (avoids allocating animation controllers/tickers)
    if (!isPlaying && !isBuffering) {
      return Semantics(
        button: true,
        label: 'تشغيل التلاوة',
        child: Container(
          width: showAyahMarkerCircle ? boxSize : null,
          height: showAyahMarkerCircle ? boxSize : null,
          margin: const EdgeInsets.symmetric(horizontal: 2.0),
          alignment: Alignment.center,
          decoration: boxDecoration,
          child: staticContent,
        ),
      );
    }

    return Semantics(
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
                    width: (boxSize * 0.48).clamp(9.5, 12.0),
                    height: (boxSize * 0.48).clamp(9.5, 12.0),
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      valueColor: AlwaysStoppedAnimation<Color>(colors.primary),
                    ),
                  )
                : isPlaying
                    ? Icon(
                        key: const ValueKey('playing'),
                        Icons.stop_rounded,
                        size: (boxSize * 0.54).clamp(11.0, 14.5),
                        color: colors.primary,
                      )
                    : staticContent,
          ),
        ),
      ),
    );
  }
}
