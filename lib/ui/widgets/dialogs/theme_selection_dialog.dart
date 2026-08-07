import 'package:flutter/material.dart';
import '../../../state/app_state.dart';

class ThemeSelectionDialog extends StatelessWidget {
  final VoidCallback onThemeSelected;

  const ThemeSelectionDialog({super.key, required this.onThemeSelected});

  @override
  Widget build(BuildContext context) {
    final app = AppState.instance;
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final c = app.colors;
        final isAr = app.isArabic;

        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24),
          child: Container(
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: c.gold.withValues(alpha: 0.1),
                  blurRadius: 40,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: c.gold.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.palette_rounded, color: c.gold, size: 24),
                ),
                const SizedBox(height: 16),
                Text(
                  isAr ? 'اختر مظهر التطبيق' : 'Choose App Theme',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: c.text,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  isAr
                      ? 'يمكنك تغيير المظهر لاحقاً من الإعدادات'
                      : 'You can change this later in settings',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: c.muted, fontSize: 14),
                ),
                const SizedBox(height: 32),
                Row(
                  children: [
                    Expanded(
                      child: _ThemeOption(
                        title: isAr ? 'أبيض' : 'White',
                        color: const Color(0xFFF9FAFB),
                        textColor: const Color(0xFF1E293B),
                        borderColor: const Color(0xFFE2E8F0),
                        onTap: () {
                          app.setTheme(AppTheme.light);
                          onThemeSelected();
                        },
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _ThemeOption(
                        title: isAr ? 'أسود' : 'Black',
                        color: const Color(0xFF0F172A),
                        textColor: const Color(0xFFF8FAFC),
                        borderColor: const Color(0xFF334155),
                        onTap: () {
                          app.setTheme(AppTheme.dark);
                          onThemeSelected();
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ThemeOption extends StatelessWidget {
  final String title;
  final Color color;
  final Color textColor;
  final Color borderColor;
  final VoidCallback onTap;

  const _ThemeOption({
    required this.title,
    required this.color,
    required this.textColor,
    required this.borderColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 100,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor, width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: Text(
          title,
          style: TextStyle(
            color: textColor,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
