import 'dart:math';

import 'lib/tracking/word/phoneme_matrix.dart';
import 'lib/tracking/common/quran_normalizer.dart';

void main() {
  String asrString = "وووَللَااهُعَزِۦۦزُ";
  String refString = "وَللَااهُ";
  
  // Fake a vocabulary that has syllables
  QuranNormalizer.initVocabulary(['وَ', 'لَ', 'هُ', 'اا', 'عَ', 'زِ', 'ۦۦ', 'زُ']);
  
  List<String> refChunks = QuranNormalizer.chunkPhonemes(refString);
  print("Ref Chunks: $refChunks");
  
  // Let's assume ASR tokens are characters because of 'ووو' causing ASR to emit characters
  List<String> asrTokens = asrString.split('');
  print("ASR Tokens: $asrTokens");
  
  PhonemeMatrix.preheat([...refChunks, ...asrTokens]);
  
  int n = refChunks.length;
  int m = asrTokens.length;
  int stride = n + 1;
  List<double> dp = List.filled((m + 1) * stride, 0.0);
  
  for (int j = 1; j <= n; j++) dp[j] = j * 1.0;
  for (int i = 1; i <= m; i++) dp[i * stride] = 0.0;
  
  for (int i = 1; i <= m; i++) {
    int row = i * stride;
    int prev = (i - 1) * stride;
    int pId = PhonemeMatrix.encode(asrTokens[i-1]);
    
    for (int j = 1; j <= n; j++) {
      int rId = PhonemeMatrix.encode(refChunks[j-1]);
      
      double sub = dp[prev + j - 1] + PhonemeMatrix.getCost(pId, rId);
      double del = dp[row + j - 1] + 1.0;
      double ins = dp[prev + j] + 1.0;
      
      dp[row + j] = min(sub, min(del, ins));
    }
  }
  
  int bestI = -1;
  double bestCost = double.infinity;
  for (int i = 1; i <= m; i++) {
    double norm = dp[i * stride + n] / n;
    print("End at i=$i (char ${asrTokens[i-1]}): norm=$norm");
    if (norm <= 0.28) {
      if (norm < bestCost) {
        bestI = i;
        bestCost = norm;
      }
    }
  }
  
  print("Final Result: bestI = $bestI, bestCost = $bestCost");
}
