import 'package:flutter/material.dart';
import '../../../state/app_state.dart';
import 'setting_tile.dart';

class TrackingStrictnessTile extends StatelessWidget {
  final ThemeColors c;
  final AppState app;
  final bool isAr;

  const TrackingStrictnessTile({
    super.key,
    required this.c,
    required this.app,
    required this.isAr,
  });

  @override
  Widget build(BuildContext context) {
    final titles = isAr ? ['سهل', 'عادي', 'صعب'] : ['Easy', 'Normal', 'Hard'];
    final descs = isAr
        ? [
            'يتجاهل أخطاء الحروف البسيطة والمدود الزائدة.',
            'تطابق متوازن. يظهر جميع الأخطاء وأحكام التجويد.',
            'تطابق دقيق جداً وحساس لأي خطأ في النطق.',
          ]
        : [
            'Hides basic letter errors & extra elongations.',
            'Balanced matching. Shows all errors and Tajweed rules.',
            'Very strict matching. Sensitive to exact pronunciation.',
          ];

    final int sel = app.trackingStrictness.index;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: c.gold.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.track_changes_rounded, color: c.gold, size: 18),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  isAr ? 'مستوى التصحيح' : 'Correction Level',
                  style: TextStyle(
                    color: c.text,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          PremiumPillSelector(
            labels: titles,
            selected: sel,
            c: c,
            onSelected: (i) {
              app.setTrackingStrictness(TrackingStrictness.values[i]);
            },
          ),
          const SizedBox(height: 16),
          // Restored explanation labels for each level
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            transitionBuilder: (child, animation) {
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, -0.1),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              );
            },
            child: Container(
              key: ValueKey(sel),
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: c.surface.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: c.border.withValues(alpha: 0.1)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(
                      Icons.info_outline_rounded,
                      color: c.text.withValues(alpha: 0.5),
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      descs[sel],
                      style: TextStyle(
                        color: c.text.withValues(alpha: 0.7),
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
