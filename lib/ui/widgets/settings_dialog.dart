import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:recite_quran/recite_quran.dart';
import '../../state/app_state.dart';
import 'settings/autoscroll_slider_tile.dart';
import 'settings/font_slider_tile.dart';
import 'settings/setting_tile.dart';

/// Settings modal bottom sheet with modern styling.
class SettingsDialog extends StatelessWidget {
  final HighlightingController? controller;

  const SettingsDialog({super.key, this.controller});

  @override
  Widget build(BuildContext context) {
    final app = AppState.instance;

    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final c = app.colors;
        final isAr = app.isArabic;

        return Directionality(
          textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.75,
            ),
            decoration: BoxDecoration(
              color: c.glassSurface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(28),
              ),
              border: Border.all(
                color: c.border.withValues(alpha: app.isDarkMode ? 0.35 : 0.6),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: app.isDarkMode ? 0.40 : 0.08),
                  blurRadius: 40,
                  offset: const Offset(0, -8),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(28),
              ),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Material(
                  color: Colors.transparent,
                  child: SafeArea(
                    top: false,
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                        const SizedBox(height: 12),

                        // ── Handle ──
                        Container(
                          width: 44,
                          height: 4,
                          decoration: BoxDecoration(
                            color: c.border,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // ── Title ──
                        Padding(
                          padding: const EdgeInsetsDirectional.symmetric(horizontal: 24),
                          child: Row(
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: c.primary.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: c.primary.withValues(alpha: 0.20),
                                    width: 1,
                                  ),
                                ),
                                child: Icon(
                                  Icons.settings_rounded,
                                  color: c.primary,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Text(
                                isAr ? 'الإعدادات' : 'Settings',
                                style: TextStyle(
                                  color: c.text,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const Spacer(),
                              // Reset Button
                              Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(10),
                                  onTap: () async {
                                    final prefs = await SharedPreferences.getInstance();
                                    await prefs.clear();
                                    if (context.mounted) {
                                      await app.load();
                                      if (context.mounted) {
                                        Navigator.of(context).pop();
                                        app.showSettingsResetBanner();
                                      }
                                    }
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    child: Text(
                                      isAr ? 'إعادة تعيين' : 'Reset',
                                      style: TextStyle(
                                        color: c.textSecondary,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),

                        // ── Application Preferences Card ──
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Container(
                            decoration: BoxDecoration(
                              color: c.surfaceHigh,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: c.border.withValues(alpha: 0.5),
                                width: 1,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: app.isDarkMode ? 0.20 : 0.03),
                                  blurRadius: 10,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Column(
                              children: [
                                // 1. Language
                                SettingTile(
                                  icon: Icons.language_rounded,
                                  title: isAr ? 'اللغة' : 'Language',
                                  c: c,
                                  trailing: PremiumPillSelector(
                                    labels: const ['عربي', 'English'],
                                    selected: isAr ? 0 : 1,
                                    c: c,
                                    onSelected: (i) {
                                      if ((i == 0 && !isAr) || (i == 1 && isAr)) {
                                        app.toggleLanguage();
                                      }
                                    },
                                  ),
                                ),
                                PremiumSettingDivider(c: c),

                                // 2. Theme
                                SettingTile(
                                  icon: Icons.palette_rounded,
                                  title: isAr ? 'مظهر التطبيق' : 'App Theme',
                                  c: c,
                                  bottom: PremiumPillSelector(
                                    labels: isAr
                                        ? ['أبيض', 'أسود']
                                        : ['White', 'Black'],
                                    selected: app.theme.index,
                                    c: c,
                                    onSelected: (i) => app.setTheme(AppTheme.values[i]),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        
                        // ── Reading Preferences Card ──
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Container(
                            decoration: BoxDecoration(
                              color: c.surfaceHigh,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: c.border.withValues(alpha: 0.5),
                                width: 1,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: app.isDarkMode ? 0.20 : 0.03),
                                  blurRadius: 10,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Column(
                              children: [
                                // 1. Font Size
                                FontSliderTile(c: c, app: app, isAr: isAr),
                                PremiumSettingDivider(c: c),

                                // 2. AutoScroll Speed
                                AutoScrollSliderTile(c: c, app: app, isAr: isAr),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),

                        // ── Footer Dua ──
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          child: Text(
                            'ربنا تقبل منا انك انت السميع العليم\nهذا من فضل ربي',
                            textAlign: TextAlign.center,
                            textDirection: TextDirection.rtl,
                            style: TextStyle(
                              color: c.primary.withValues(alpha: 0.35),
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              height: 1.6,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
}
