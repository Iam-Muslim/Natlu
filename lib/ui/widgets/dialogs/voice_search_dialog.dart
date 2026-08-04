import 'package:flutter/material.dart';
import '../../../state/app_state.dart';

/// Modal dialog shown when voice search is actively listening for an Ayah recitation.
class VoiceSearchDialog extends StatelessWidget {
  final VoidCallback onStop;

  const VoiceSearchDialog({super.key, required this.onStop});

  /// Static helper to display the voice search dialog.
  static void show(BuildContext context, {required VoidCallback onStop}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.15),
      builder: (_) => VoiceSearchDialog(onStop: onStop),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = AppState.instance;
    final c = app.colors;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40),
      child: Container(
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: c.gold.withValues(alpha: 0.25), width: 1),
          boxShadow: [
            BoxShadow(
              color: c.gold.withValues(alpha: 0.1),
              blurRadius: 30,
              spreadRadius: 0,
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Stop Button ──
              GestureDetector(
                onTap: onStop,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: c.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: c.red.withValues(alpha: 0.25),
                      width: 1.5,
                    ),
                  ),
                  child: Icon(Icons.stop_rounded, color: c.red, size: 28),
                ),
              ),
              const SizedBox(height: 18),

              // ── Listening Instruction Text ──
              Text(
                app.isArabic
                    ? 'اتلو آية من القران العظيم للانتقال اليها'
                    : 'Recite an Ayah from the Quran to jump to it',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: c.text,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
