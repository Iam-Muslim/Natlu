import 'line.dart';
import 'word.dart';

/// Exact mirror of Page.ts in mushaf-svelte.
/// Represents a complete 15-line Mushaf page.
class Page {
  final int pageNumber;
  final List<Line> lines;
  final (int surah, int ayah)? firstAyah;
  final Word? lastWord;
  final int? dominantSurah;
  final Set<String> ayahKeys;

  const Page({
    required this.pageNumber,
    required this.lines,
    this.firstAyah,
    this.lastWord,
    this.dominantSurah,
    this.ayahKeys = const {},
  });

  /// Factory method to parse lines JSON exactly like Page.fromJSON in Svelte,
  /// resolving all words to aya_ui Unicode PUA characters with HafsSmart glyphs.
  static Page fromJSON({
    required int pageNumber,
    required List<dynamic> rawLines,
    required Map<String, List<String>> ayahTokensMap,
  }) {
    final List<Line> parsedLines = [];
    final Set<String> pageAyahs = {};
    final Map<int, int> surahWordCounts = {};
    (int, int)? firstAyahFound;
    Word? lastWordFound;

    for (int i = 0; i < rawLines.length; i++) {
      final lineItem = rawLines[i];
      if (lineItem is! Map) continue;
      final lineMap = Map<String, dynamic>.from(lineItem);
      final String lineType = lineMap['t'] as String? ?? lineMap['type'] as String? ?? 'text';

      switch (lineType) {
        case 'surah-header':
        case 'header':
          final surahNum = lineMap['s'] as int? ??
              int.tryParse(lineMap['surah']?.toString() ?? '1') ?? 1;
          final surahName = lineMap['name'] as String? ??
              lineMap['text'] as String? ?? 'سورة $surahNum';
          parsedLines.add(SurahHeaderLine(surahNumber: surahNum, surahName: surahName));
          break;

        case 'basmala':
          int basmalaSurah = 1;
          if (i + 1 < rawLines.length && rawLines[i + 1] is Map) {
            final nextMap = rawLines[i + 1] as Map;
            final wList = nextMap['w'] as List? ?? nextMap['words'] as List?;
            if (wList != null && wList.isNotEmpty) {
              final loc = (wList.first is Map ? (wList.first['location'] ?? '') : wList.first).toString();
              final colon = loc.indexOf(':');
              if (colon > 0) {
                basmalaSurah = int.tryParse(loc.substring(0, colon)) ?? 1;
              }
            }
          }
          parsedLines.add(BasmalaLine(surahNumber: basmalaSurah));
          break;

        case 'text':
        default:
          final wordsData = lineMap['w'] as List? ?? lineMap['words'] as List? ?? const [];
          final List<Word> words = [];

          for (final wItem in wordsData) {
            String location = '';
            String standardWord = '';

            if (wItem is Map) {
              location = wItem['location']?.toString() ?? '';
              standardWord = wItem['word']?.toString() ?? '';
            } else {
              location = wItem.toString();
            }

            final parts = location.split(':');
            if (parts.length >= 3) {
              final s = int.parse(parts[0]);
              final a = int.parse(parts[1]);
              final w1 = int.parse(parts[2]);
              final ayahKey = '$s:$a';

              pageAyahs.add(ayahKey);
              surahWordCounts[s] = (surahWordCounts[s] ?? 0) + 1;
              firstAyahFound ??= (s, a);

              final tokens = ayahTokensMap[ayahKey];
              String puaText = standardWord;
              bool isAyahEnd = false;
              String? ayahMarkerGlyph;

              if (tokens != null && tokens.isNotEmpty) {
                if (tokens.length == 1) {
                  puaText = tokens[0];
                  isAyahEnd = true;
                } else {
                  final wordCount = tokens.length - 1; // last token is the ayah number marker
                  final w0 = (w1 - 1).clamp(0, wordCount - 1);
                  puaText = tokens[w0];
                  isAyahEnd = (w1 >= wordCount);
                  if (isAyahEnd) {
                    ayahMarkerGlyph = tokens.last;
                  }
                }
              }

              final parsedWord = Word(
                location: location,
                word: standardWord.isNotEmpty ? standardWord : puaText,
                text: puaText,
                isAyahEnd: isAyahEnd,
                ayahMarkerGlyph: ayahMarkerGlyph,
              );
              words.add(parsedWord);
              lastWordFound = parsedWord;
            }
          }

          final rawText = lineMap['text'] as String? ?? '';
          final rawVerseRange = lineMap['verseRange'] as String? ?? '';
          parsedLines.add(TextLine(words: words, text: rawText, verseRange: rawVerseRange));
          break;
      }
    }

    int? dominant;
    int maxCount = -1;
    surahWordCounts.forEach((s, count) {
      if (count > maxCount) {
        maxCount = count;
        dominant = s;
      }
    });
    dominant ??= firstAyahFound?.$1;

    return Page(
      pageNumber: pageNumber,
      lines: List.unmodifiable(parsedLines),
      firstAyah: firstAyahFound,
      lastWord: lastWordFound,
      dominantSurah: dominant,
      ayahKeys: Set.unmodifiable(pageAyahs),
    );
  }
}
