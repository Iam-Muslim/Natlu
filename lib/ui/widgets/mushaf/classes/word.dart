/// Exact mirror of Word.ts in mushaf-svelte.
/// Represents a single Quranic word in the Mushaf layout.
class Word {
  final String location; // e.g. "2:255:1" (surah:ayah:wordIndex1)
  final String word;     // Standard Arabic word text
  final String text;     // Unicode PUA glyph text from aya_ui for HafsSmart font
  final bool isAyahEnd;  // True if this word is the final word of an Ayah
  final String? ayahMarkerGlyph; // Authentic HafsSmart PUA glyph with ayah number inside
  final int surah;
  final int ayah;
  final int wordIndex0;

  const Word({
    required this.location,
    required this.word,
    required this.text,
    this.isAyahEnd = false,
    this.ayahMarkerGlyph,
    this.surah = 1,
    this.ayah = 1,
    this.wordIndex0 = 0,
  });

  /// Extracts the Surah number from pre-parsed integer (O(1))
  int? getSurahNumber() => surah;

  /// Extracts the Verse (Ayah) number from pre-parsed integer (O(1))
  int? getVerseNumber() => ayah;

  /// Extracts the 0-indexed word index from pre-parsed integer (O(1))
  int getWordIndex0() => wordIndex0;
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
