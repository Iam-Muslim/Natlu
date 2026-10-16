/// Exact mirror of Word.ts in mushaf-svelte.
/// Represents a single Quranic word in the Mushaf layout.
class Word {
  final String location; // e.g. "2:255:1" (surah:ayah:wordIndex1)
  final String word;     // Standard Arabic word text
  final String text;     // Unicode PUA glyph text from aya_ui for HafsSmart font
  final bool isAyahEnd;  // True if this word is the final word of an Ayah
  final String? ayahMarkerGlyph; // Authentic HafsSmart PUA glyph with ayah number inside

  const Word({
    required this.location,
    required this.word,
    required this.text,
    this.isAyahEnd = false,
    this.ayahMarkerGlyph,
  });

  /// Extracts the Surah number from location (e.g. "2:255:1" -> 2)
  int? getSurahNumber() {
    final colon = location.indexOf(':');
    if (colon <= 0) return null;
    return int.tryParse(location.substring(0, colon));
  }

  /// Extracts the Verse (Ayah) number from location (e.g. "2:255:1" -> 255)
  int? getVerseNumber() {
    final colon1 = location.indexOf(':');
    if (colon1 <= 0) return null;
    final colon2 = location.indexOf(':', colon1 + 1);
    if (colon2 <= colon1) return null;
    return int.tryParse(location.substring(colon1 + 1, colon2));
  }

  /// Extracts the 0-indexed word index for audio/speech tracking (e.g. "2:255:1" -> 0)
  int getWordIndex0() {
    final colon1 = location.indexOf(':');
    if (colon1 <= 0) return 0;
    final colon2 = location.indexOf(':', colon1 + 1);
    if (colon2 <= colon1) return 0;
    final w1 = int.tryParse(location.substring(colon2 + 1)) ?? 1;
    return (w1 - 1).clamp(0, 999);
  }
}

/// Typed word reference within a Mushaf page for tracking and playback
class MushafWordRef {
  final int surah;
  final int ayah;
  final int wordIndex1;
  final int wordIndex0;
  final String text;

  const MushafWordRef({
    required this.surah,
    required this.ayah,
    required this.wordIndex1,
    required this.wordIndex0,
    required this.text,
  });
}
