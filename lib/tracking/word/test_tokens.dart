import 'dart:io';

void main() {
  final file = File('../../../assets/model/tokens.txt');
  final lines = file.readAsLinesSync();
  for (var line in lines) {
    if (line.contains('ڇ') || line.contains('ں') || line.contains('مِ')) {
      print(line);
    }
  }
}
