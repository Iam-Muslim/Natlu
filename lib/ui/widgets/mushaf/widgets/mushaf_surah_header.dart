import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:recite_quran/recite_quran.dart';

import '../../../../state/app_state.dart';
import '../../verse_row.dart';

/// Modern Flat Surah Header Banner:
/// - Clean card container styled strictly with app theme tokens.
/// - Pure centered Surah title in authentic Arabic typography.
/// - Fits effortlessly inside the 15-flex Expanded Column from qcf_quran_plus.
class MushafSurahHeader extends StatelessWidget {
  final int surahNum;
  final String surahName;
  final double? lineWidth;
  final double? lineHeight;
  final double? fontSize;
  final ThemeColors colors;
  final AppState app;
  final HighlightingController controller;
  final VoidCallback? onAyahSelected;

  static final RegExp _tashkeelRegex = RegExp(r'[\u064B-\u065F\u0670]');
  static final Map<int, String> _cleanSurahNamesCache = {};

  const MushafSurahHeader({
    super.key,
    required this.surahNum,
    required this.surahName,
    this.lineWidth,
    this.lineHeight,
    this.fontSize,
    required this.colors,
    required this.app,
    required this.controller,
    this.onAyahSelected,
  });

  @override
  Widget build(BuildContext context) {
    final bool isDark = app.isDarkMode;
    final double bannerHeight = lineHeight != null
        ? (lineHeight! * 0.82).clamp(20.0, 32.0)
        : 30.0;

    final String displayName = _cleanSurahNamesCache.putIfAbsent(
      surahNum,
      () => surahName.replaceAll(_tashkeelRegex, ''),
    );

    return SizedBox(
      width: lineWidth ?? double.infinity,
      height: lineHeight,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.lightImpact();
          VerseRow.selectAyah(
            surah: surahNum,
            ayah: 1,
            controller: controller,
            onTap: onAyahSelected,
          );
        },
        child: Center(
          child: Container(
            width: lineWidth ?? double.infinity,
            height: bannerHeight,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colors.surfaceHigh,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: colors.border.withValues(alpha: isDark ? 0.70 : 0.85),
                width: 0.85,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
                  blurRadius: 6,
                  offset: const Offset(0, 1.5),
                ),
              ],
            ),
            child: Text(
              displayName,
              textAlign: TextAlign.center,
              textDirection: TextDirection.rtl,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'cairo',
                fontSize: (bannerHeight * 0.50).clamp(12.0, 16.5),
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
                color: colors.text,
                height: 1.25,
                leadingDistribution: TextLeadingDistribution.even,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
