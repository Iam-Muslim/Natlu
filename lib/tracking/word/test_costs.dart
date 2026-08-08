import 'phoneme_matrix.dart';

void main() {
  print("Testing ںںں vs ن");
  print("Cost: ${SubCostTable.getCost('ںںں', 'ن')}");
  
  print("Testing ںںں vs نْ");
  print("Cost: ${SubCostTable.getCost('ںںں', 'نْ')}");
  
  print("Testing بڇ vs بْ");
  print("Cost: ${SubCostTable.getCost('بڇ', 'بْ')}");
  
  print("Testing ں vs ن");
  print("Cost: ${SubCostTable.getCost('ں', 'ن')}");
  
  print("Testing بڇ vs ب");
  print("Cost: ${SubCostTable.getCost('بڇ', 'ب')}");
}
