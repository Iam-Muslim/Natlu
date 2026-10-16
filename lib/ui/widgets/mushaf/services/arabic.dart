/// Exact mirror of ArabicService in mushaf-svelte (src/lib/services/arabic.ts).
class ArabicService {
  static const List<String> _arabicNumbers = [
    '٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'
  ];

  static String latinToArabicNumbers(dynamic input) {
    final str = input.toString();
    final buffer = StringBuffer();
    for (int i = 0; i < str.length; i++) {
      final codeUnit = str.codeUnitAt(i);
      if (codeUnit >= 48 && codeUnit <= 57) {
        buffer.write(_arabicNumbers[codeUnit - 48]);
      } else {
        buffer.write(str[i]);
      }
    }
    return buffer.toString();
  }
}
