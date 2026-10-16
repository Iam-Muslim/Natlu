import 'package:flutter/material.dart';
import '../../../../state/app_state.dart';
import '../services/arabic.dart';

/// Clean Mushaf Footer:
/// Displays ONLY the Eastern Arabic page number centered at the bottom.
class FooterWidget extends StatelessWidget {
  final int pageNumber;
  final int? pageSurah;
  final String? surahName;
  final ThemeColors colors;

  const FooterWidget({
    super.key,
    required this.pageNumber,
    this.pageSurah,
    this.surahName,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 4.0),
      alignment: Alignment.center,
      child: Text(
        ArabicService.latinToArabicNumbers(pageNumber),
        style: TextStyle(
          fontFamily: 'HafsSmart',
          fontSize: 18.0,
          fontWeight: FontWeight.bold,
          color: colors.text,
        ),
      ),
    );
  }
}
