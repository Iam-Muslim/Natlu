import 'package:flutter_test/flutter_test.dart';
import 'asr_chunk_simulator.dart';
import 'matching_harness.dart';
import 'quran_data_loader.dart';

void main() {
  test('Trace remaining discrepancies in Surah 7, 21, 42', () async {
    final dataLoader = await SimulationQuranDataLoader.loadFromProjectRoot('.');

    // 1. Trace Surah 7 Ayah 20
    {
      final harness = MatchingHarness.create();
      final surahWords = dataLoader.getSurahWords(7);
      final phonemeWords = surahWords.map((w) => w.phoneme).toList();
      final boundaries = dataLoader.calculateBoundaries(phonemeWords);
      final fullPhonemes = phonemeWords.join('');

      harness.setSurahReference(
        surahNumber: 7,
        fullPhonemes: fullPhonemes,
        boundaries: boundaries,
        isTajweed: false,
        forceClear: true,
        startGlobalWord: 0,
      );

      final verses = dataLoader.getSurahVerses(7);
      print('\n=== SURAH 7 AYAHS 19-21 ===');
      for (int a = 0; a < 22; a++) {
        final verse = verses[a];
        final isTarget = (verse.ayah == 20);
        final frames = AsrChunkSimulator.simulateStreamingAccretion(
          verse.phonemeWords,
          baseTokenDuration: 0.08,
          interWordPause: 0.10,
        );
        final configuredFrames = <AsrStreamFrame>[];
        for (int f = 0; f < frames.length; f++) {
          configuredFrames.add(
            AsrStreamFrame(
              tokens: frames[f].tokens,
              timestamps: frames[f].timestamps,
              isNewSegment: (f == 0),
              debugDescription: frames[f].debugDescription,
            ),
          );
        }

        if (isTarget) {
          print('--- AYAH 20 WORDS ---');
          for (int w = 0; w < verse.phonemeWords.length; w++) {
            print('  W$w: "${verse.phonemeWords[w]}"');
          }
          for (int f = 0; f < configuredFrames.length; f++) {
            final frame = configuredFrames[f];
            print('  [F$f] Tokens (${frame.tokens.length}): "${frame.tokens.join(' ')}" | Cursor: ${harness.sequencer.targetWordCursor}');
            await harness.feedFrames([frame], ayahNumber: verse.ayah);
            for (final log in harness.capture.debugEvents) {
              print('  [F$f] LOG: ${log.message}');
            }
            for (final ev in harness.capture.matchedEvents) {
              print('  [F$f] 🎯 MATCHED Word ${ev.wordId} (Red: ${ev.isRed}) | Asr: "${ev.cleanAsr}"');
            }
            harness.capture.debugEvents.clear();
            harness.capture.matchedEvents.clear();
          }
        } else {
          await harness.feedFrames(configuredFrames, ayahNumber: verse.ayah);
        }
      }
      print('Surah 7 Reds: ${harness.capture.redWordIds}');
    }

    // 2. Trace Surah 21 Ayah 40
    {
      final harness = MatchingHarness.create();
      final surahWords = dataLoader.getSurahWords(21);
      final phonemeWords = surahWords.map((w) => w.phoneme).toList();
      final boundaries = dataLoader.calculateBoundaries(phonemeWords);
      final fullPhonemes = phonemeWords.join('');

      harness.setSurahReference(
        surahNumber: 21,
        fullPhonemes: fullPhonemes,
        boundaries: boundaries,
        isTajweed: false,
        forceClear: true,
        startGlobalWord: 0,
      );

      final verses = dataLoader.getSurahVerses(21);
      print('\n=== SURAH 21 AYAHS 38-41 ===');
      for (int a = 0; a < 41; a++) {
        final verse = verses[a];
        final isTarget = (verse.ayah == 40);
        final frames = AsrChunkSimulator.simulateStreamingAccretion(
          verse.phonemeWords,
          baseTokenDuration: 0.08,
          interWordPause: 0.10,
        );
        final configuredFrames = <AsrStreamFrame>[];
        for (int f = 0; f < frames.length; f++) {
          configuredFrames.add(
            AsrStreamFrame(
              tokens: frames[f].tokens,
              timestamps: frames[f].timestamps,
              isNewSegment: (f == 0),
              debugDescription: frames[f].debugDescription,
            ),
          );
        }

        if (isTarget) {
          print('--- AYAH 40 WORDS ---');
          for (int w = 0; w < verse.phonemeWords.length; w++) {
            print('  W$w: "${verse.phonemeWords[w]}"');
          }
          for (int f = 0; f < configuredFrames.length; f++) {
            final frame = configuredFrames[f];
            print('  [F$f] Tokens (${frame.tokens.length}): "${frame.tokens.join(' ')}" | Cursor: ${harness.sequencer.targetWordCursor}');
            await harness.feedFrames([frame], ayahNumber: verse.ayah);
            for (final log in harness.capture.debugEvents) {
              print('  [F$f] LOG: ${log.message}');
            }
            for (final ev in harness.capture.matchedEvents) {
              print('  [F$f] 🎯 MATCHED Word ${ev.wordId} (Red: ${ev.isRed}) | Asr: "${ev.cleanAsr}"');
            }
            harness.capture.debugEvents.clear();
            harness.capture.matchedEvents.clear();
          }
        } else {
          await harness.feedFrames(configuredFrames, ayahNumber: verse.ayah);
        }
      }
      print('Surah 21 Reds: ${harness.capture.redWordIds}');
    }

    // 3. Trace Surah 42 Ayah 38-39
    {
      final harness = MatchingHarness.create();
      final surahWords = dataLoader.getSurahWords(42);
      final phonemeWords = surahWords.map((w) => w.phoneme).toList();
      final boundaries = dataLoader.calculateBoundaries(phonemeWords);
      final fullPhonemes = phonemeWords.join('');

      harness.setSurahReference(
        surahNumber: 42,
        fullPhonemes: fullPhonemes,
        boundaries: boundaries,
        isTajweed: false,
        forceClear: true,
        startGlobalWord: 0,
      );

      final verses = dataLoader.getSurahVerses(42);
      print('\n=== SURAH 42 AYAHS 37-40 ===');
      for (int a = 0; a < 40; a++) {
        final verse = verses[a];
        final isTarget = (verse.ayah == 38 || verse.ayah == 39);
        final frames = AsrChunkSimulator.simulateStreamingAccretion(
          verse.phonemeWords,
          baseTokenDuration: 0.08,
          interWordPause: 0.10,
        );
        final configuredFrames = <AsrStreamFrame>[];
        for (int f = 0; f < frames.length; f++) {
          configuredFrames.add(
            AsrStreamFrame(
              tokens: frames[f].tokens,
              timestamps: frames[f].timestamps,
              isNewSegment: (f == 0),
              debugDescription: frames[f].debugDescription,
            ),
          );
        }

        if (isTarget) {
          print('--- AYAH ${verse.ayah} WORDS ---');
          for (int w = 0; w < verse.phonemeWords.length; w++) {
            print('  W$w: "${verse.phonemeWords[w]}"');
          }
          for (int f = 0; f < configuredFrames.length; f++) {
            final frame = configuredFrames[f];
            print('  [F$f] Tokens (${frame.tokens.length}): "${frame.tokens.join(' ')}" | Cursor: ${harness.sequencer.targetWordCursor}');
            await harness.feedFrames([frame], ayahNumber: verse.ayah);
            for (final log in harness.capture.debugEvents) {
              print('  [F$f] LOG: ${log.message}');
            }
            for (final ev in harness.capture.matchedEvents) {
              print('  [F$f] 🎯 MATCHED Word ${ev.wordId} (Red: ${ev.isRed}) | Asr: "${ev.cleanAsr}"');
            }
            harness.capture.debugEvents.clear();
            harness.capture.matchedEvents.clear();
          }
        } else {
          await harness.feedFrames(configuredFrames, ayahNumber: verse.ayah);
        }
      }
      print('Surah 42 Reds: ${harness.capture.redWordIds}');
    }
  });
}
