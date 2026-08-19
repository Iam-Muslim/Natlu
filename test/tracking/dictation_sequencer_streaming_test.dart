import 'dart:async';
import 'dart:isolate';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_great_quran/tracking/word/dictation_sequencer.dart';
import 'package:the_great_quran/tracking/word/phoneme_alignment_isolate.dart';
import 'package:the_great_quran/data/quran_data.dart';

void main() {
  group('DictationSequencer Streaming Tests (DP Mathematical Stability)', () {
    // ── Reference for Surah 1:1 (Al-Fatihah 1:1) ──
    const String fullPhonemes1_1 = 'بِسمِللَااهِررَحمَاانِررَحِۦۦۦۦم';
    final List<int> boundaries1_1 = [0, 5, 12, 22, 32];
    
    late ReceivePort receivePort;
    late DictationSequencer sequencer;
    late List<Map<String, dynamic>> emittedEvents;
    late StreamSubscription subscription;

    setUp(() {
      receivePort = ReceivePort();
      emittedEvents = [];
      subscription = receivePort.listen((message) {
        if (message is Map<String, dynamic>) {
          emittedEvents.add(message);
        }
      });

      sequencer = DictationSequencer(receivePort.sendPort);
      
      // Inject test data directly to bypass File I/O (QuranData)
      sequencer.wordBoundaries = boundaries1_1;
      sequencer.fullPhonemes = fullPhonemes1_1;
      sequencer.isTajweed = true;
      sequencer.currentSurahNumber = 1;
      
      // Target rules for Word 0 (بسم), Word 1 (لله), Word 2 (الرحمن), Word 3 (الرحيم)
      sequencer.surahWordRules = [
        [], // Word 0
        [
          const WordTajweedRule(ruleId: 1, nameAr: 'المد الطبيعي', nameEn: 'Natural Madd', goldenLen: 2),
          const WordTajweedRule(ruleId: 9, nameAr: 'الشدة', nameEn: 'Shaddah', goldenLen: 1)
        ], // Word 1
        [
          const WordTajweedRule(ruleId: 1, nameAr: 'المد الطبيعي', nameEn: 'Natural Madd', goldenLen: 2),
          const WordTajweedRule(ruleId: 9, nameAr: 'الشدة', nameEn: 'Shaddah', goldenLen: 1)
        ], // Word 2
        [
          const WordTajweedRule(ruleId: 5, nameAr: 'المد العارض للسكون', nameEn: 'Aared Madd', goldenLen: 4),
          const WordTajweedRule(ruleId: 9, nameAr: 'الشدة', nameEn: 'Shaddah', goldenLen: 1)
        ], // Word 3
      ];
      
      // Initialize internal tracking state manually
      sequencer.targetWordCursor = 0;
      sequencer.asrCharAnchor = 0;
      sequencer.committedGreenWords.clear();
      sequencer.committedRedWords.clear();
      sequencer.lastMatchedPhoneme = null;
    });

    tearDown(() {
      subscription.cancel();
      receivePort.close();
    });

    /// Helper to simulate live ASR streaming character by character
    Future<void> simulateStream(String text, {double timePerChar = 0.10}) async {
      String buffer = '';
      List<double> timestamps = [];
      for (int i = 0; i < text.length; i++) {
        buffer += text[i];
        timestamps.add(timePerChar);
        sequencer.syncStream(SyncStreamCommand(
          asrText: buffer,
          timestamps: List.from(timestamps),
        ));
        
        // Yield to microtask queue to allow receivePort to process messages
        await Future.delayed(Duration.zero);
      }
    }

    test('1. Dangling Vowel Cascade Prevention (<= bestCost Fix)', () async {
      await simulateStream('بِسمُ');
      final matches0Partial = emittedEvents.where((e) => e['event'] == 'highlight' && e['word_id'] == 0).toList();
      expect(matches0Partial.isEmpty, isTrue, reason: 'Word 0 should wait because bestCost > 0.0 at frontier');

      emittedEvents.clear();
      await simulateStream('بِسمُللَااهِ');
      
      final matches0 = emittedEvents.where((e) => e['event'] == 'highlight' && e['word_id'] == 0).toList();
      expect(matches0.isNotEmpty, isTrue, reason: 'Word 0 should commit once user moves on');
      
      final matches1 = emittedEvents.where((e) => e['event'] == 'highlight' && e['word_id'] == 1).toList();
      expect(matches1.isNotEmpty, isTrue, reason: 'Word 1 should match cleanly without vowel pollution');
    });

    test('2. Tajweed Frontier Protection (isPartial == true)', () async {
      sequencer.targetWordCursor = 3;
      sequencer.asrCharAnchor = 0; 
      
      // Action: Feed "ررَحِۦ" (User is actively pronouncing the word, hasn't reached the final م)
      await simulateStream('ررَحِۦ');
      
      // Expected: Because bestI == m and the matrix has trailing deletions for the Madd and final م, 
      // the `isPartial` flag correctly triggers, and it WAITS.
      final matchesPartial = emittedEvents.where((e) => e['event'] == 'highlight' && e['word_id'] == 3).toList();
      expect(matchesPartial.isEmpty, isTrue, reason: 'Should wait while user is still speaking trailing letters');

      // Action: User finishes the word perfectly
      await simulateStream('ررَحِۦۦۦۦم', timePerChar: 0.25); // Slow down to pass Tajweed duration
      
      final matchesAfter = emittedEvents.where((e) => e['event'] == 'highlight' && e['word_id'] == 3).toList();
      expect(matchesAfter.isNotEmpty, isTrue, reason: 'Should commit instantly when word is complete');
      expect(matchesAfter.first['is_red'], isFalse, reason: 'Perfect recitation must be green');
    });

    test('3. Normal Continuous Perfect Speech', () async {
      // timePerChar = 0.3 ensures all Madds and Shaddahs meet their golden duration requirements
      await simulateStream('بِسمِللَااهِررَحمَاانِررَحِۦۦۦۦم', timePerChar: 0.30);
      
      final allMatches = emittedEvents.where((e) => e['event'] == 'highlight').toList();
      
      // Since it's a perfect recitation, all 4 words should be matched cleanly
      expect(allMatches.length, equals(4));
      
      for (int i = 0; i < 4; i++) {
        expect(allMatches[i]['word_id'], equals(i));
        expect(allMatches[i]['is_red'], isFalse, reason: 'Perfect recitation should have no red words');
      }
    });

    test('4. Strict Frontier Rule - Cascade Prevention (ءِييَااكَ نَعبُدُ)', () async {
      // Define a custom sequencer specifically for this test
      final String ayah5Phonemes = 'ءِييَااكَ نَعبُدُ';
      final List<int> ayah5Boundaries = [0, 10, 16]; // ءِييَااكَ (0-9, space is 9), نَعبُدُ (10-15)
      
      final seq = DictationSequencer(
        receivePort.sendPort,
      );
      seq.wordBoundaries = ayah5Boundaries;
      seq.fullPhonemes = ayah5Phonemes;
      seq.isTajweed = true;
      seq.currentSurahNumber = 1;
      
      seq.targetWordCursor = 0; // Word 0: ءِييَااكَ
      seq.asrCharAnchor = 0;
      
      // Simulate feeding ءِييَاا
      String buffer = '';
      List<double> ts = [];
      for (int i = 0; i < 'ءِييَاا'.length; i++) {
        buffer += 'ءِييَاا'[i];
        ts.add(0.25);
        seq.syncStream(SyncStreamCommand(asrText: buffer, timestamps: List.from(ts)));
        await Future.delayed(Duration.zero);
      }
      
      // Expected: Because bestCost > 0.0 (missing كَ) and we are at the frontier (bestI == m),
      // the `isPartial` flag should correctly trigger, and it should WAIT.
      final matches13Partial = emittedEvents.where((e) => e['event'] == 'highlight' && e['word_id'] == 0).toList();
      expect(matches13Partial.isEmpty, isTrue, reason: 'Should wait because word has errors and is at frontier');

      // Action 2: Feed "كَ نَعبُدُ" (User finishes the word and says the next)
      // Now buffer is "ءِييَااكَ نَعبُدُ"
      final String fullString = 'ءِييَااكَ نَعبُدُ';
      for (int i = buffer.length; i < fullString.length; i++) {
        buffer += fullString[i];
        ts.add(0.25);
        seq.syncStream(SyncStreamCommand(asrText: buffer, timestamps: List.from(ts)));
        await Future.delayed(Duration.zero);
      }
      
      // Expected: Word 0 is instantly committed because bestI < m.
      // Word 1 is instantly committed because it's perfect.
      final matches13 = emittedEvents.where((e) => e['event'] == 'highlight' && e['word_id'] == 0).toList();
      expect(matches13.isNotEmpty, isTrue, reason: 'Should commit Word 0 instantly once user moves on');
      
      final matches14 = emittedEvents.where((e) => e['event'] == 'highlight' && e['word_id'] == 1).toList();
      expect(matches14.isNotEmpty, isTrue, reason: 'Should commit Word 1 perfectly without cascade');
    });
  });
}
