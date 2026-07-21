import 'package:flutter/foundation.dart';

class DebugLogger {
  static String _currentAsrBuffer = '';
  static String _lastPrintedLeft = '';

  /// Updates the cached ASR buffer that will be printed on the left side of the table.
  static void updateAsrBuffer(String buffer) {
    _currentAsrBuffer = buffer;
  }

  /// Reverses Arabic character sequences so they display correctly LTR in Windows/VSCode terminals.
  static String fixArabicForTerminal(String input) {
    // If there's no Arabic, return early to save time.
    if (!RegExp(r'[\u0600-\u06FF]').hasMatch(input)) return input;

    // We match contiguous blocks of Arabic characters (including spaces between them)
    // and reverse the entire block.
    return input.replaceAllMapped(RegExp(r'[\u0600-\u06FF\s]+'), (match) {
      String segment = match.group(0)!;
      // Reverse characters inside the segment.
      return segment.split('').reversed.join('');
    });
  }

  /// Calculates visual length by ignoring 0-width Arabic diacritics.
  static int _getVisualLength(String text) {
    int length = 0;
    for (int i = 0; i < text.length; i++) {
      int code = text.codeUnitAt(i);
      // Skip Arabic diacritics (Tashkeel) as they render on top of letters
      if (code >= 0x0610 && code <= 0x061A) continue;
      if (code >= 0x064B && code <= 0x065F) continue;
      if (code == 0x0670) continue;
      length++;
    }
    return length;
  }

  /// Pad or truncate a string to a fixed visual width.
  static String _padRight(String text, int width) {
    int vLen = _getVisualLength(text);
    if (vLen > width) {
      return text.substring(0, width - 3) + '...';
    }
    return text + (' ' * (width - vLen));
  }

  static String _getRecentAsr(String text, int maxLen) {
    if (text.length <= maxLen) return text;
    // Keep the most recent characters (the end of the string)
    return '...' + text.substring(text.length - maxLen + 3);
  }

  static void printStateIfChanged() {
    if (_currentAsrBuffer.isEmpty) return;
    String leftCol = _padRight('', 100);
    String recentAsr = _getRecentAsr(_currentAsrBuffer, 60);
    String rightCol = fixArabicForTerminal(recentAsr);
    
    if (rightCol != _lastPrintedLeft) { // Reuse _lastPrintedLeft to track the rightCol state
      debugPrint('$leftCol │ $rightCol');
      _lastPrintedLeft = rightCol;
    }
  }

  /// Central logging method with split-column layout.
  static void log(String tag, String message) {
    // 1. Prepare left column (Event Message)
    String leftMessage = '[$tag] $message';
    leftMessage = fixArabicForTerminal(leftMessage);
    String leftCol = _padRight(leftMessage, 100);

    // 2. Prepare right column (ASR Buffer)
    String recentAsr = _getRecentAsr(_currentAsrBuffer, 60);
    String rightCol = fixArabicForTerminal(recentAsr);

    // 3. Print the formatted row
    // Format: EVENT_MESSAGE_PADDED │ ASR_BUFFER
    debugPrint('$leftCol │ $rightCol');
    _lastPrintedLeft = rightCol;
  }

  /// Simple log for things that don't need the split column (like initialization)
  static void logSimple(String tag, String message) {
    debugPrint('[$tag] ${fixArabicForTerminal(message)}');
  }
}
