import 'package:flutter/material.dart';
import '../../../state/app_state.dart';

class StrictnessSelectionDialog extends StatelessWidget {
  final VoidCallback onStrictnessSelected;

  const StrictnessSelectionDialog({super.key, required this.onStrictnessSelected});

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
                  child: Icon(
                    Icons.tune_rounded,
                    color: c.gold,
                    size: 24,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  isAr ? 'دقة التتبع' : 'Tracking Strictness',
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
                    ? 'يمكنك تغيير مستوى الدقة لاحقاً من الإعدادات'
                    : 'You can change this later in settings',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: c.muted,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 32),
                
                _StrictnessOption(
                  title: isAr ? 'طبيعي' : 'Normal',
                  subtitle: isAr 
                      ? 'تتبع متوازن. يظهر جميع الأخطاء وأحكام التجويد.'
                      : 'Balanced matching. Shows all errors and Tajweed rules.',
                  isSelected: app.trackingStrictness == TrackingStrictness.normal,
                  c: c,
                  onTap: () {
                    app.setTrackingStrictness(TrackingStrictness.normal);
                    onStrictnessSelected();
                  },
                ),
                const SizedBox(height: 12),
                _StrictnessOption(
                  title: isAr ? 'صارم' : 'Strict',
                  subtitle: isAr 
                      ? 'تتبع دقيق جداً. يتطلب نطقاً خالياً من أي شوائب.'
                      : 'Highly sensitive. Requires pristine pronunciation.',
                  isSelected: app.trackingStrictness == TrackingStrictness.strict,
                  c: c,
                  onTap: () {
                    app.setTrackingStrictness(TrackingStrictness.strict);
                    onStrictnessSelected();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _StrictnessOption extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool isSelected;
  final ThemeColors c;
  final VoidCallback onTap;

  const _StrictnessOption({
    required this.title,
    required this.subtitle,
    required this.isSelected,
    required this.c,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? c.gold.withValues(alpha: 0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? c.gold : c.border.withValues(alpha: 0.3),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              color: isSelected ? c.gold : c.muted,
              size: 20,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: isSelected ? c.gold : c.text,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: c.muted,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
