import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:recite_quran/recite_quran.dart';
import '../../../state/app_state.dart';

/// Pure helper for generating high-performance, styled [InlineSpan] lists for Quranic verses.
/// Handles zero-GPU blur hiding, color status resolution, and word gesture binding.
class VerseSpanBuilder {
  /// Resolves the foreground color for word at index [wordIndex].
  static Color resolveWordColor({
    required int ayah,
    required int wordIndex,
    required HighlightingController controller,
    required ThemeColors colors,
  }) {
    if (wordIndex < 0) return colors.text;
    if (controller.isWordGreen(ayah, wordIndex)) return colors.green;
    if (controller.isWordRed(ayah, wordIndex)) return colors.red;
    if (controller.isWordYellow(ayah, wordIndex)) return colors.warning;
    return colors.text;
  }

  /// Resolves the word display color, handling zero-GPU blur hiding for unrecited words.
  static Color resolveWordDisplayColor({
    required int ayah,
    required int wordIndex,
    required HighlightingController controller,
    required AppState app,
    required ThemeColors colors,
    required bool isAutoScrolling,
  }) {
    if (wordIndex < 0) return colors.text;
    final isRead = controller.isWordGreen(ayah, wordIndex) ||
        controller.isWordRed(ayah, wordIndex) ||
        controller.isWordYellow(ayah, wordIndex) ||
        controller.isWordNeutral(ayah, wordIndex);

    final isHidden = app.isBlurMode && !isRead && !isAutoScrolling;
    return isHidden
        ? Colors.transparent
        : resolveWordColor(
            ayah: ayah,
            wordIndex: wordIndex,
            controller: controller,
            colors: colors,
          );
  }

  /// Builds the complete list of [InlineSpan]s representing an Ayah's text.
  static List<InlineSpan> buildSpans({
    required List<String> words,
    required int ayah,
    required bool isActive,
    required bool isAutoScrolling,
    bool isRecording = false,
    required HighlightingController controller,
    required AppState app,
    required ThemeColors colors,
    required List<TapGestureRecognizer> recognizersSink,
    required VoidCallback? onVerseTap,
    required void Function(int ayah, int wordIndex, String word) onWordErrorTap,
    void Function(int ayah, int wordIndex)? onWordAudioTap,
  }) {
    final List<InlineSpan> spans = [];
    final bool enableGestures = !isAutoScrolling;

    final TextStyle defaultStyle = TextStyle(
      fontFamily: 'HafsSmart',
      fontSize: app.fontSize,
      height: 2.6,
      wordSpacing: 5.0,
      color: colors.text,
    );

    const InlineSpan spaceSpan = TextSpan(
      text: ' ',
      style: TextStyle(
        fontFamily: 'HafsSmart',
        wordSpacing: 5.0,
      ),
    );

    for (int i = 0; i < words.length; i++) {
      final Color color = resolveWordDisplayColor(
        ayah: ayah,
        wordIndex: i,
        controller: controller,
        app: app,
        colors: colors,
        isAutoScrolling: isAutoScrolling,
      );

      final word = words[i];
      final wordIdx = i;

      TapGestureRecognizer? recognizer;
      if (enableGestures) {
        recognizer = TapGestureRecognizer()
          ..onTap = () {
            if (controller.isWordYellow(ayah, wordIdx)) {
              onWordErrorTap(ayah, wordIdx, word);
            } else {
              onWordAudioTap?.call(ayah, wordIdx);
            }
          };
        recognizersSink.add(recognizer);
      }

      final TextStyle? style = (color == colors.text)
          ? defaultStyle
          : defaultStyle.copyWith(color: color);

      // ALWAYS add the word as a standard TextSpan!
      spans.add(
        TextSpan(
          text: word,
          style: style,
          recognizer: recognizer,
        ),
      );

      // Word separator
      if (i < words.length - 1) {
        spans.add(spaceSpan);
      }
    }

    return spans;
  }
}
