import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:recite_quran/recite_quran.dart';

import '../../../../state/app_state.dart';
import '../../verse_row.dart';

/// Authentic Mushaf Calligraphy Basmala Line Widget
class MushafBasmala extends StatelessWidget {
  final int basmalaSurah;
  final double lineWidth;
  final double lineHeight;
  final double fontSize;
  final String wordFontFamily;
  final ThemeColors colors;
  final HighlightingController controller;
  final bool isAutoScrolling;
  final VoidCallback? onAyahSelected;

  const MushafBasmala({
    super.key,
    required this.basmalaSurah,
    required this.lineWidth,
    required this.lineHeight,
    required this.fontSize,
    required this.wordFontFamily,
    required this.colors,
    required this.controller,
    required this.isAutoScrolling,
    this.onAyahSelected,
  });

  @override
  Widget build(BuildContext context) {
    final basmalaVerse = controller.repository.getVerse(1, 1);
    final List<String> words =
        (basmalaVerse != null && basmalaVerse.uthmaniWords.length >= 4)
            ? basmalaVerse.uthmaniWords.sublist(0, 4)
            : const ['بِسْمِ', 'ٱللَّهِ', 'ٱلرَّحْمَـٰنِ', 'ٱلرَّحِيمِ'];
    final bool usesUthmani =
        basmalaVerse != null && basmalaVerse.uthmaniWords.length >= 4;

    return SizedBox(
      width: lineWidth,
      height: lineHeight,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (isAutoScrolling) return;
          HapticFeedback.lightImpact();
          VerseRow.selectAyah(
            surah: basmalaSurah,
            ayah: 1,
            controller: controller,
            onTap: onAyahSelected,
          );
        },
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
                      SizedBox(width: (fontSize * 0.18).clamp(3.0, 5.0)),
                    Text(
                      words[i],
                      textDirection: TextDirection.rtl,
                      textScaler: TextScaler.noScaling,
                      style: TextStyle(
                        fontFamily: usesUthmani ? wordFontFamily : 'cairo',
                        fontSize: (fontSize * 0.52).clamp(9.5, 13.5),
                        fontWeight: FontWeight.normal,
                        color: colors.text,
                        height: 1.2,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
