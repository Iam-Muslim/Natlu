import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import '../lib/tracking/word/dictation_sequencer.dart';
import '../lib/tracking/word/phoneme_alignment_isolate.dart';

Future<void> main() async {
  final file = File('assets/model/ordered_quran_phonemes.json');
  if (!file.existsSync()) {
    print('Error: ordered_quran_phonemes.json not found!');
    return;
  }

  final String jsonStr = await file.readAsString();
  final Map<String, dynamic> jsonMap = jsonDecode(jsonStr);

  final logFile = File('test_results_log.txt');
  final sink = logFile.openWrite();

  sink.writeln('--- STARTING MATCHING SIMULATION ---');

  int totalAyahsProcessed = 0;

  for (final entry in jsonMap.entries) {
    if (totalAyahsProcessed >= 6236) break;

    final key = entry.key; // e.g. "1:1"
    final data = entry.value as Map<String, dynamic>;
    final surahNum = int.parse(key.split(':')[0]);
    final ayahNum = int.parse(key.split(':')[1]);

    String ayaPhoneme = data['aya_phoneme'] ?? '';
    List<dynamic> rawList = data['aya_phonemes_list'] ?? [];
    List<String> words = rawList.map((e) => e.toString()).toList();
    if (words.isEmpty) continue;

    List<int> boundaries = [0];
    int currentLen = 0;
    for (String w in words) {
      currentLen += w.length;
      boundaries.add(currentLen);
    }
    
    // Scenario A: Perfect ASR chunks
    await runScenario(sink, 'SCENARIO_A_PERFECT', surahNum, ayahNum, ayaPhoneme, words, boundaries, (String w) => w);
    
    // Scenario B: Missing word (skip middle word)
    if (words.length > 2) {
      await runScenario(sink, 'SCENARIO_B_MISSING_WORD', surahNum, ayahNum, ayaPhoneme, words, boundaries, (String w) {
        if (w == words[words.length ~/ 2]) return ''; 
        return w;
      });
    }

    // Scenario C: Noisy word (add junk to every word)
    await runScenario(sink, 'SCENARIO_C_NOISY', surahNum, ayahNum, ayaPhoneme, words, boundaries, (String w) {
      return w + 'ا';
    });

    totalAyahsProcessed++;
    if (totalAyahsProcessed % 100 == 0) {
      print('Processed $totalAyahsProcessed ayahs...');
    }
  }

  sink.writeln('--- SIMULATION COMPLETED ---');
  await sink.close();
  print('Done. Results saved to test_results_log.txt');
}

Future<void> runScenario(
  IOSink sink, 
  String scenarioName, 
  int surahNum, 
  int ayahNum, 
  String fullPhonemes, 
  List<String> words, 
  List<int> boundaries,
  String Function(String) mutateWord
) async {
  final receivePort = ReceivePort();
  final sequencer = DictationSequencer(receivePort.sendPort);

  sequencer.setSurahReference(SetSurahReferenceCommand(
    fullPhonemes: fullPhonemes,
    boundaries: boundaries,
    surahNumber: surahNum,
    isTajweed: false,
    trackingStrictness: 'normal',
    forceClear: true,
  ));

  int currentTarget = 0;

  // Collect events
  List<IsolateEvent> events = [];
  final sub = receivePort.listen((message) {
    if (message is Map) {
      try {
        final evt = IsolateEvent.fromMap(message);
        events.add(evt);
      } catch (e) {
        // ignore debug events
      }
    }
  });

  String asrBuffer = '';
  
  for (int i = 0; i < words.length; i++) {
    String originalWord = words[i];
    String mutatedWord = mutateWord(originalWord);
    if (mutatedWord.isEmpty) continue; // skipped word

    // Generate chunks for the current word and append to ASR buffer
    // Simulate real ASR behavior by sending chunks of the new word
    for (int j = 1; j <= mutatedWord.length; j++) {
      String chunk = mutatedWord.substring(0, j);
      String fullAsrChunk = asrBuffer.isEmpty ? chunk : asrBuffer + ' ' + chunk;
      
      sequencer.syncStream(SyncStreamCommand(
        asrText: fullAsrChunk,
        timestamps: [],
        ysProbs: [],
      ));

      // Yield to the event loop so the ReceivePort can receive the messages sent by SendPort
      await Future.delayed(Duration.zero);

      // Process events that were triggered
      while (events.isNotEmpty) {
        final evt = events.removeAt(0);
        if (evt is WordMatchedEvent) {
          currentTarget = sequencer.targetWordCursor;

          // Failures Analysis
          if (scenarioName == 'SCENARIO_A_PERFECT') {
            if (evt.isRed) {
              sink.writeln('[$scenarioName] WRONG RED | Surah: $surahNum Ayah: $ayahNum | Word: $originalWord | Score: ${evt.score}');
            }
          } else if (scenarioName == 'SCENARIO_C_NOISY') {
            if (!evt.isRed) { 
              sink.writeln('[$scenarioName] WRONG GREEN | Surah: $surahNum Ayah: $ayahNum | Word: $originalWord | Mutated: $mutatedWord | Score: ${evt.score}');
            }
          }
        }
      }
    }
    
    // Finalize the word buffer
    asrBuffer = asrBuffer.isEmpty ? mutatedWord : asrBuffer + ' ' + mutatedWord;
  }

  // Check if stuck
  if (currentTarget < words.length && scenarioName == 'SCENARIO_A_PERFECT') {
    sink.writeln('[$scenarioName] STUCK | Surah: $surahNum Ayah: $ayahNum | Stuck at index $currentTarget out of ${words.length}');
  }

  await sub.cancel();
  receivePort.close();
}
