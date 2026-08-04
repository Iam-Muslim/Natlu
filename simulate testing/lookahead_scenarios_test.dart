import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_great_quran/tracking/word/dictation_matcher.dart';
import 'package:the_great_quran/tracking/word/quran_normalizer.dart';
import 'package:the_great_quran/tracking/word/phoneme_matrix.dart';
import 'package:the_great_quran/data/quran_data.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Continuous Words Lookahead Test Suite', () {
    List<QuranVerse> verses = [];
    List<String> surahWords = [];
    List<String> refChunks = [];
    List<int> chunkToWordMap = [];
    List<int> wordBoundaries = [0];
    late int wordCount;
    late List<int> wordStartChunk;
    late List<int> wordEndChunk;
    late List<bool> startBd;
    late List<bool> endBd;
    final matcher = ForwardDictationMatcher();

    setUpAll(() async {
      final tokenFile = File('assets/model/tokens.txt');
      if (tokenFile.existsSync()) {
        final lines = await tokenFile.readAsLines();
        List<String> tokens = [];
        for (var line in lines) {
          var parts = line.split(' ');
          if (parts.isNotEmpty) tokens.add(parts[0]);
        }
        PhonemeMatrix.preheat(tokens);
      }

      final dbFile = File('assets/model/ordered_quran_phonemes.json');
      if (!dbFile.existsSync()) throw Exception('Database not found.');
      final Map<String, dynamic> phonemesList = jsonDecode(await dbFile.readAsString());

      for (final entry in phonemesList.entries) {
        final keyParts = entry.key.split(':');
        if (keyParts.length == 2) {
          final surahNum = int.tryParse(keyParts[0]) ?? 1;
          final ayahNum = int.tryParse(keyParts[1]) ?? 1;
          if (surahNum == 1) {
            verses.add(QuranVerse.fromJson(surahNum, ayahNum, entry.value as Map<String, dynamic>));
          }
        }
      }
      verses.sort((a, b) => a.ayah.compareTo(b.ayah));

      int globalWordIdx = 0;
      for (var verse in verses.take(2)) {
        for (int i = 0; i < verse.phonemeWords.length; i++) {
          String w = verse.phonemeWords[i];
          if (w.isEmpty) continue;
          surahWords.add(w);
          final chunks = QuranNormalizer.chunkPhonemes(w);
          refChunks.addAll(chunks);
          for (int c = 0; c < chunks.length; c++) {
            chunkToWordMap.add(globalWordIdx);
          }
          globalWordIdx++;
          wordBoundaries.add(wordBoundaries.last + w.replaceAll(' ', '').length);
        }
      }

      wordCount = globalWordIdx;
      wordStartChunk = List.filled(wordCount, 0);
      wordEndChunk = List.filled(wordCount, 0);
      for (int j = 0; j < refChunks.length; j++) {
        int w = chunkToWordMap[j];
        if (w < wordCount) {
          if (j == 0 || chunkToWordMap[j - 1] != w) {
            wordStartChunk[w] = j;
          }
          wordEndChunk[w] = j + 1;
        }
      }

      int n = refChunks.length;
      startBd = List.filled(n + 1, false);
      endBd = List.filled(n + 1, false);
      if (n > 0) {
        startBd[0] = true;
        for (int j = 1; j < n; j++) {
          if (chunkToWordMap[j] != chunkToWordMap[j - 1]) {
            startBd[j] = true;
            endBd[j] = true;
          }
        }
        startBd[n] = false;
        endBd[n] = true;
      }
    });

    Map<String, dynamic> simulateSequence({
      required int initialCursor,
      required String asrText,
      String strictness = 'normal',
    }) {
      List<PhonemeToken> cleanTokens = QuranNormalizer.chunkPhonemesWithIndices(asrText);
      int asrConsumedTokenCount = 0;
      int targetWordCursor = initialCursor;

      List<int> redWords = [];
      List<int> greenWords = [];

      bool matchedSomething;
      do {
        matchedSomething = false;
        if (targetWordCursor >= wordCount) break;

        if (cleanTokens.length < asrConsumedTokenCount) {
          asrConsumedTokenCount = cleanTokens.length;
        }

        List<PhonemeToken> unconsumedTokens = cleanTokens.sublist(asrConsumedTokenCount);
        if (unconsumedTokens.isEmpty) break;

        int m = unconsumedTokens.length;
        List<String> unconsumedStrings = unconsumedTokens.map((t) => t.text).toList();

        int lookaheadWords = strictness == 'easy' ? 0 : 3;
        int audioRefEndWord = targetWordCursor;
        int refPhonemeCount = 0;
        for (int i = wordStartChunk[targetWordCursor]; i < refChunks.length; i++) {
          refPhonemeCount++;
          audioRefEndWord = chunkToWordMap[i];
          if (refPhonemeCount >= m) break;
        }

        int endWordLimit = (strictness == 'easy')
            ? targetWordCursor
            : min(
                wordCount - 1,
                max(targetWordCursor + lookaheadWords, audioRefEndWord + 2),
              );

        int winStartChunk = wordStartChunk[targetWordCursor];
        int winEndChunk = (endWordLimit < wordEndChunk.length)
            ? wordEndChunk[endWordLimit]
            : refChunks.length;

        List<String> targetWindow = refChunks.sublist(winStartChunk, winEndChunk);
        List<int> targetWordIds = chunkToWordMap.sublist(winStartChunk, winEndChunk);
        List<bool> targetStartBd = startBd.sublist(winStartChunk, winEndChunk + 1);
        List<bool> targetEndBd = endBd.sublist(winStartChunk, winEndChunk + 1);

        double threshold = strictness == 'easy' ? 0.35 : (strictness == 'strict' ? 0.15 : 0.25);

        AlignmentResult? result = matcher.align(
          currentAsrChunks: unconsumedStrings,
          targetWindow: targetWindow,
          targetStartBd: targetStartBd,
          targetEndBd: targetEndBd,
          targetWordIds: targetWordIds,
          expectedWord: targetWordCursor,
          threshold: threshold,
          requireStableTail: false,
          debugLog: print,
        );

        if (result == null) {
          break;
        }

        int matchedWordStart = targetWordIds[result.bestStartJ < targetWindow.length ? result.bestStartJ : targetWindow.length - 1];
        int matchedWordEnd = targetWordIds[result.bestJ - 1];

        for (int w = targetWordCursor; w <= matchedWordEnd; w++) {
          bool isSkipped = (w < matchedWordStart) || !result.words.any((match) => match.wordId == w);
          if (isSkipped) {
            redWords.add(w);
          } else {
            greenWords.add(w);
          }
        }

        asrConsumedTokenCount += result.bestI;
        targetWordCursor = matchedWordEnd + 1;
        matchedSomething = true;
      } while (matchedSomething);

      return {
        'redWords': redWords,
        'greenWords': greenWords,
        'finalCursor': targetWordCursor,
        'consumedTokens': asrConsumedTokenCount,
      };
    }

    test('Scenario 1: Sequential Utterance: بسم الله الرحمن الرحيم', () {
      String asr1 = 'بِسمِ للَااهِ ررَحمَاانِ ررَحِۦۦۦۦم';
      var res1 = simulateSequence(initialCursor: 0, asrText: asr1);
      expect(res1['redWords'], isEmpty);
      expect(res1['greenWords'], [0, 1, 2, 3]);
      expect(res1['finalCursor'], 4);
    });

    test('Scenario 2: Intra-Ayah Lookahead / Skip with Garbage: تبارك الله الرحمن الرحيم', () {
      String asr2 = 'تَبَاارَكَ للَااهِ ررَحمَاانِ ررَحِۦۦۦۦم';
      var res2 = simulateSequence(initialCursor: 0, asrText: asr2);
      expect(res2['redWords'], [0]); // Word 0 (بسم) is RED
      expect(res2['greenWords'], [1, 2, 3]); // Words 1,2,3 (الله الرحمن الرحيم) are GREEN
      expect(res2['finalCursor'], 4);
    });

    test('Scenario 3: Cross-Ayah Lookahead: Initial at Word 3 (الرحيم), user says الحمد لله', () {
      String asr3 = 'ءَلحَمدُ لِللَااهِ';
      var res3 = simulateSequence(initialCursor: 3, asrText: asr3);
      expect(res3['redWords'], [3]); // Word 3 (الرحيم) is RED
      expect(res3['greenWords'], [4, 5]); // Words 4,5 (الحمد لله) are GREEN
      expect(res3['finalCursor'], 6);
    });

    test('Scenario 4: Full Multi-Ayah Sequence with Cross-Ayah Skip in one utterance: بسم الله الرحمن الحمد لله', () {
      String asr4 = 'بِسمِ للَااهِ ررَحمَاانِ ءَلحَمدُ لِللَااهِ';
      var res4 = simulateSequence(initialCursor: 0, asrText: asr4);
      expect(res4['greenWords'], [0, 1, 2, 4, 5]);
      expect(res4['redWords'], [3]); // Word 3 (الرحيم) was skipped -> RED
      expect(res4['finalCursor'], 6);
    });

    test('Scenario 5: Easy Mode (0 Lookahead) only matches current word', () {
      // User says word 1 (الله) while cursor is at word 0 (بسم) in easy mode.
      // Since easy mode only looks at current word, it should NOT lookahead jump to word 1.
      String asr5 = 'للَااهِ';
      var res5 = simulateSequence(initialCursor: 0, asrText: asr5, strictness: 'easy');
      expect(res5['greenWords'], isEmpty); // Does not match because word 0 is expected
      expect(res5['finalCursor'], 0);
    });
  });
}
