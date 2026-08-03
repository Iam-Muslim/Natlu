import 'dart:convert';
import 'dart:io';

import 'package:the_great_quran/tracking/word/dictation_matcher.dart';
import 'package:the_great_quran/tracking/word/quran_normalizer.dart';
import 'package:the_great_quran/tracking/word/phoneme_matrix.dart';
import 'package:the_great_quran/data/quran_data.dart';

void main() async {
  print('===========================================');
  print('⛏️ MINING SHERPA SUBSTITUTION BIASES');
  print('===========================================');

  final dbFile = File('assets/model/ordered_quran_phonemes.json');
  if (!dbFile.existsSync()) {
    print('Database not found.');
    return;
  }
  
  final dbData = await dbFile.readAsString();
  final Map<String, dynamic> phonemesList = jsonDecode(dbData);
  
  List<QuranVerse> verses = [];
  for (final entry in phonemesList.entries) {
    final keyParts = entry.key.split(':');
    if (keyParts.length == 2) {
      final surahNum = int.tryParse(keyParts[0]) ?? 1;
      final ayahNum = int.tryParse(keyParts[1]) ?? 1;
      final phonemeObj = entry.value as Map<String, dynamic>;
      verses.add(QuranVerse.fromJson(surahNum, ayahNum, phonemeObj));
    }
  }
  verses.sort((a, b) {
    if (a.surah != b.surah) return a.surah.compareTo(b.surah);
    return a.ayah.compareTo(b.ayah);
  });

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

  final testDataFile = File('simulate testing/batch_streaming_test_data.json');
  if (!testDataFile.existsSync()) {
    print('batch_streaming_test_data.json not found.');
    return;
  }
  
  final batchData = jsonDecode(await testDataFile.readAsString()) as List;
  final matcher = ForwardDictationMatcher();
  
  Map<String, int> substitutionFrequencies = {};

  for (var scenario in batchData) {
    int surah = scenario['surah'];
    int startAyah = scenario['start_ayah'];
    int endAyah = scenario['end_ayah'];
    List<dynamic> frames = scenario['frames'];
    
    // Prepare Reference Data
    final List<String> refChunks = [];
    final List<int> chunkToWordMap = [];
    
    int wordIndexOffset = 0;
    for (int ayah = startAyah; ayah <= endAyah; ayah++) {
      final verse = verses.firstWhere((v) => v.surah == surah && v.ayah == ayah, orElse: () => verses.first);
      if (verse.surah != surah) continue;
      
      for (int i = 0; i < verse.phonemeWords.length; i++) {
        String wordPhoneme = verse.phonemeWords[i];
        if (wordPhoneme.isEmpty) continue;
        
        final chunks = QuranNormalizer.chunkPhonemes(wordPhoneme);
        refChunks.addAll(chunks);
        for (int c = 0; c < chunks.length; c++) {
          chunkToWordMap.add(wordIndexOffset + i);
        }
      }
      wordIndexOffset += verse.phonemeWords.length;
    }
    
    List<bool> startBd = List.filled(refChunks.length + 1, false);
    List<bool> endBd = List.filled(refChunks.length + 1, false);

    if (refChunks.isNotEmpty) {
      startBd[0] = true;
      for (int j = 1; j < refChunks.length; j++) {
        if (chunkToWordMap[j] != chunkToWordMap[j - 1]) {
          startBd[j] = true;
          endBd[j] = true;
        }
      }
      startBd[refChunks.length] = false;
      endBd[refChunks.length] = true;
    }
    
    // True Streaming Loop
    int targetWordCursor = 0;
    int consumedTokensCount = 0;
    
    for (var frame in frames) {
      String currentAsrText = frame['text'] as String;
      if (currentAsrText.isEmpty) continue;
      
      List<String> asrTokens = QuranNormalizer.chunkPhonemes(currentAsrText);
      final List<String> currentCleanTokens = asrTokens
          .where((t) => t.trim().isNotEmpty && t != '<blank>' && t != 'ؙ')
          .toList();
          
      if (currentCleanTokens.length < consumedTokensCount) {
         consumedTokensCount = currentCleanTokens.length;
      }
      
      final List<String> cleanAsr = currentCleanTokens.sublist(consumedTokensCount);
      if (cleanAsr.isEmpty) continue;
      
      // Setup DP window
      int winStartChunk = -1;
      int winEndChunk = -1;
      for (int i = 0; i < refChunks.length; i++) {
        if (chunkToWordMap[i] == targetWordCursor && winStartChunk == -1) {
          winStartChunk = i;
        }
        if (chunkToWordMap[i] <= targetWordCursor + 3) {
          winEndChunk = i;
        }
      }
      
      if (winStartChunk == -1) break;
      
      final windowRefChunks = refChunks.sublist(winStartChunk, winEndChunk + 1);
      final windowStartBd = startBd.sublist(winStartChunk, winEndChunk + 2);
      final windowEndBd = endBd.sublist(winStartChunk, winEndChunk + 2);
      final windowWordIds = chunkToWordMap.sublist(winStartChunk, winEndChunk + 1);
      
      final result = matcher.align(
        currentAsrChunks: cleanAsr,
        targetWindow: windowRefChunks,
        targetStartBd: windowStartBd,
        targetEndBd: windowEndBd,
        targetWordIds: windowWordIds,
        expectedWord: targetWordCursor,
        threshold: 0.35, 
      );
      
      if (result != null && result.words.isNotEmpty) {
        
        // ---------------------------------------------------------
        // MINING TRACE
        // ---------------------------------------------------------
        for (var align in result.trace) {
          if (align.opType == 'replace') { // 'replace' = Substitution
             if (align.refIdx >= 0 && align.predIdx >= 0) {
                 String refP = windowRefChunks[align.refIdx];
                 String predP = cleanAsr[align.predIdx];
                 
                 // Extract base letters for matrix logic mapping
                 String baseRef = refP.isNotEmpty ? refP[0] : '';
                 String basePred = predP.isNotEmpty ? predP[0] : '';
                 
                 if (baseRef != basePred && baseRef.isNotEmpty && basePred.isNotEmpty) {
                    String pairKey = '$baseRef -> $basePred';
                    substitutionFrequencies[pairKey] = (substitutionFrequencies[pairKey] ?? 0) + 1;
                 }
             }
          }
        }
        
        for (var word in result.words) {
          if (word.wordId == targetWordCursor) {
            targetWordCursor++;
          } else if (word.wordId > targetWordCursor) {
            targetWordCursor = word.wordId + 1;
          }
        }
        
        if (result.bestI > 0 && result.bestI <= cleanAsr.length) {
          consumedTokensCount += result.bestI;
        }
      }
    }
  }
  
  print('\n📊 SUBSTITUTION FREQUENCIES (Base Letters Only):');
  
  var sortedKeys = substitutionFrequencies.keys.toList()
    ..sort((k1, k2) => substitutionFrequencies[k2]!.compareTo(substitutionFrequencies[k1]!));
    
  for (var key in sortedKeys) {
    if (substitutionFrequencies[key]! >= 2) {
       print('   ${key.padRight(8)} : ${substitutionFrequencies[key]} times');
    }
  }
  print('===========================================\n');
}
