import 'word.dart';

/// Exact mirror of Line.ts in mushaf-svelte.
/// Base class representing a single line on a Mushaf page.
abstract class Line {
  final String type; // 'text' | 'basmala' | 'surah-header'

  const Line(this.type);
}

/// Represents a Surah header banner line.
class SurahHeaderLine extends Line {
  final int surahNumber;
  final String surahName;

  const SurahHeaderLine({
    required this.surahNumber,
    required this.surahName,
  }) : super('surah-header');
}

/// Represents a standard Quranic text line composed of words.
class TextLine extends Line {
  final List<Word> words;
  final String text;
  final String verseRange;

  const TextLine({
    required this.words,
    this.text = '',
    this.verseRange = '',
  }) : super('text');
}

/// Represents a Basmala line centered between surahs.
class BasmalaLine extends Line {
  final int? surahNumber;

  const BasmalaLine({this.surahNumber}) : super('basmala');
}
