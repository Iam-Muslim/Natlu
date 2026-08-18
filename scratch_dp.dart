import 'dart:math';
import 'dart:typed_data';

void main() {
  String ref = "وَللَااهُ";
  String asr = "و  وووَللَااهُعَزِۦۦزُ";
  
  List<String> refTokens = ref.split('');
  List<String> asrTokens = asr.split('');
  
  int n = refTokens.length;
  int m = asrTokens.length;
  
  int stride = n + 1;
  Float64List dp = Float64List((m + 1) * stride);
  
  dp[0] = 0.0;
  for (int j = 1; j <= n; j++) dp[j] = j * 1.0;
  for (int i = 1; i <= m; i++) dp[i * stride] = 0.0;
  
  for (int i = 1; i <= m; i++) {
    int row = i * stride;
    int prev = (i - 1) * stride;
    
    for (int j = 1; j <= n; j++) {
      double sub = dp[prev + j - 1] + (asrTokens[i-1] == refTokens[j-1] ? 0.0 : 1.0);
      double del = dp[row + j - 1] + 1.0;
      double ins = dp[prev + j] + 1.0;
      
      dp[row + j] = min(sub, min(del, ins));
    }
  }
  
  int bestI = -1;
  double bestCost = double.infinity;
  for (int i = 1; i <= m; i++) {
    double norm = dp[i * stride + n] / n;
    print("i=$i ('${asrTokens[i-1]}') norm=$norm");
    if (norm <= 0.28) {
      if (norm < bestCost) {
        bestI = i;
        bestCost = norm;
      }
    }
  }
  
  print("bestI=$bestI bestCost=$bestCost");
}
