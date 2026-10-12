// Global application state singleton.
//
// Manages all user-configurable settings (language, theme, font size,
// blur mode, auto-scroll) and exposes the active [ThemeColors]
// palette. All UI widgets listen to this via [ChangeNotifier].
//
// Design: Zero-persistence — settings reset on app restart.
// This keeps the codebase dependency-free and startup instant.

import 'dart:async';
import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:recite_quran/recite_quran.dart';
import '../services/quran_audio_service.dart';

// Supported UI languages.
enum AppLanguage { ar, en }

// Application Mode: Word Checker (Sherpa) vs Tajweed (Muaalem)
enum AppMode { wordChecker, tajweed }


// Available color themes: White and Black.
enum AppTheme { white, black }

// Failure reasons for audio streaming & API fetch.
enum AudioFailureReason {
  networkOffline,
  serverUnavailable,
  rateLimited,
  unknown,
}

class AppState extends ChangeNotifier {
  AppState._() {
    // Initialize default language from the device's OS setting.
    final deviceLang = ui.PlatformDispatcher.instance.locale.languageCode;
    _lang = (deviceLang == 'ar') ? AppLanguage.ar : AppLanguage.en;
  }

  /// Singleton instance — accessed everywhere as `AppState.instance`.
  static final AppState instance = AppState._();

  // ── Language ───────────────────────────────────────────────────────────────

  late AppLanguage _lang;
  AppLanguage get lang => _lang;
  bool get isArabic => _lang == AppLanguage.ar;

  void toggleLanguage() async {
    _lang = _lang == AppLanguage.ar ? AppLanguage.en : AppLanguage.ar;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('lang', _lang.name);
  }

  // ── Mode ───────────────────────────────────────────────────────────────────

  AppMode currentMode = AppMode.wordChecker;
  int tajweedClickCount = 0;
  bool get hasClickedTajweedWord => tajweedClickCount >= 10;

  void setMode(AppMode mode) {
    if (currentMode != mode) {
      currentMode = mode;
      notifyListeners();
    }
  }

  Future<void> markTajweedWordClicked() async {
    if (tajweedClickCount < 10) {
      tajweedClickCount++;
      notifyListeners();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('tajweed_click_count', tajweedClickCount);
    }
  }

  // ── Theme ──────────────────────────────────────────────────────────────────

  AppTheme _theme = AppTheme.white;
  AppTheme get theme => _theme;
  bool get isDarkMode => _theme == AppTheme.black;
  bool get isBlack => _theme == AppTheme.black;
  bool get isWhite => _theme == AppTheme.white;
  bool get isOled => _theme == AppTheme.black;
  bool get isParchment => false;

  void setTheme(AppTheme t) async {
    _theme = t;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme', _theme.name);
  }

  // ── Blur Mode ──────────────────────────────────────────────────────────────

  bool isBlurMode = false;

  void toggleBlurMode() async {
    isBlurMode = !isBlurMode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('blurMode', isBlurMode);
  }

  // ── Mushaf Layout Mode (Bypassed) ──────────────────────────────────────────
  // Deactivated to ensure optimal 60 FPS verse scrolling stability.
  bool isMushafLayout = false;

  void toggleMushafLayout() {
    // Bypassed: disabled
  }

  // ── Auto-Scroll Speed ──────────────────────────────────────────────────────

  static const List<double> autoScrollMultipliers = [0.25, 0.5, 1.0, 1.5, 3.0, 4.5, 6.0];
  static const List<String> speedLabels = ['0.25x', '0.5x', '1.0x', '1.5x', '2.0x', '2.5x', '3.0x'];

  int autoScrollSpeed = 2; // 2 = 1.0x (index in new array)
  bool hasChosenAutoScrollSpeed = false;

  void setAutoScrollSpeed(int speed) async {
    autoScrollSpeed = speed;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('autoScrollSpeed', autoScrollSpeed);
  }

  void setHasChosenAutoScrollSpeed(bool chosen) async {
    hasChosenAutoScrollSpeed = chosen;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('has_chosen_speed', chosen);
  }

  void cycleAutoScrollSpeed() {
    final next = (autoScrollSpeed + 1) % autoScrollMultipliers.length;
    setAutoScrollSpeed(next);
  }

  // ── Font Size ──────────────────────────────────────────────────────────────

  double fontSize = 28.0;

  void setFontSize(double size) async {
    fontSize = size;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('fontSize', fontSize);
  }

  // ── Tracker Configuration ──────────────────────────────────────────────────
  // Tajweed and Dictation modes use standard normal calibration with auto-reanchor enabled.
  TrackerConfig _trackerConfig = TrackerConfig.normal(enableAutoReanchor: true);
  TrackerConfig get trackerConfig => _trackerConfig;

  // ── Verse Audio Playback (UI state ready for backend audio wiring) ───────────
  /// Currently active audio verse playback.
  final ValueNotifier<int?> activeAudioAyah = ValueNotifier<int?>(null);
  final ValueNotifier<int?> activeAudioSurah = ValueNotifier<int?>(null);
  final ValueNotifier<bool> isAudioPlaying = ValueNotifier<bool>(false);

  /// Whether audio is actively connecting or buffering, providing instant feedback on tap.
  final ValueNotifier<bool> isAudioBuffering = ValueNotifier<bool>(false);

  /// Active word index (0-based) inside the active audio Ayah, synchronized to audio playback.
  final ValueNotifier<int?> activeAudioWordIndex = ValueNotifier<int?>(null);

  /// Determines whether playback automatically advances to next Ayah (continuous mode)
  /// or stops after playing a single Ayah (record mode).
  final ValueNotifier<bool> isContinuousPlayback = ValueNotifier<bool>(true);

  /// Whether the non-distracting audio playback failure banner is currently visible.
  bool isAudioErrorBannerVisible = false;
  AudioFailureReason lastAudioFailureReason = AudioFailureReason.networkOffline;
  Timer? _audioErrorTimer;

  /// Dispatches an audio failure event to display the serene banner.
  void triggerAudioError([AudioFailureReason reason = AudioFailureReason.networkOffline]) {
    lastAudioFailureReason = reason;
    isAudioErrorBannerVisible = true;
    _audioErrorTimer?.cancel();
    notifyListeners();

    _audioErrorTimer = Timer(const Duration(milliseconds: 4500), () {
      isAudioErrorBannerVisible = false;
      notifyListeners();
    });
  }

  /// Immediately dismisses the audio error banner.
  void dismissAudioError() {
    _audioErrorTimer?.cancel();
    if (isAudioErrorBannerVisible) {
      isAudioErrorBannerVisible = false;
      notifyListeners();
    }
  }

  /// Toggles play/pause state for a specific verse.
  /// When [continuous] is true (outside record mode), playback advances to the next Ayah on finish.
  /// When [continuous] is false (in record mode), only this single Ayah is played.
  void toggleVerseAudio({
    required int surah,
    required int ayah,
    bool continuous = true,
  }) {
    if (activeAudioSurah.value == surah &&
        activeAudioAyah.value == ayah &&
        isAudioPlaying.value) {
      QuranAudioService.instance.pause();
    } else if (activeAudioSurah.value == surah &&
               activeAudioAyah.value == ayah &&
               QuranAudioService.instance.isPaused) {
      QuranAudioService.instance.resume();
    } else {
      QuranAudioService.instance.play(
        surah: surah,
        ayah: ayah,
        continuous: continuous,
      );
    }
  }

  /// Advances playback to the next Ayah if continuous mode is active.
  /// Stops playback if [isContinuousPlayback] is false (e.g. record mode) or if surah end is reached.
  void onAyahAudioFinished({int? totalAyahsInSurah}) {
    if (!isAudioPlaying.value) return;

    if (!isContinuousPlayback.value) {
      // In record mode: single ayah only per click
      stopVerseAudio();
      return;
    }

    // Out of record mode: advance to next ayah
    final currentAyah = activeAudioAyah.value;
    final currentSurah = activeAudioSurah.value;
    if (currentAyah == null || currentSurah == null) {
      stopVerseAudio();
      return;
    }

    final maxAyah = totalAyahsInSurah ?? 286;
    if (currentAyah < maxAyah) {
      QuranAudioService.instance.play(
        surah: currentSurah,
        ayah: currentAyah + 1,
        continuous: true,
      );
    } else {
      stopVerseAudio();
    }
  }

  /// Pauses or stops active verse audio playback.
  void stopVerseAudio() {
    isAudioBuffering.value = false;
    QuranAudioService.instance.stop();
  }

  // ── Colors ─────────────────────────────────────────────────────────────────

  /// Returns the active color palette based on the current theme.
  ThemeColors get colors {
    switch (_theme) {
      case AppTheme.white:
        return _whiteColors;
      case AppTheme.black:
        return _blackColors;
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // WHITE THEME — Warm Natural Linen (Zero Glare, Eye-Comfortable)
  // Warm ivory foundation (#FAF8F5), soft clean surfaces, gentle borders,
  // deep charcoal typography (#1E293B) to avoid harsh optical glare.
  // ──────────────────────────────────────────────────────────────────────────
  static const ThemeColors _whiteColors = ThemeColors(
    bg: Color(0xFFFAF8F5),             // Warm natural linen paper (minimizes blue light)
    surface: Color(0xFFFFFFFF),        // Clean white card surface
    surfaceHigh: Color(0xFFF4F0E8),    // Soft warm elevation layer 1
    surfaceVariant: Color(0xFFEBE5D8), // Soft warm elevation layer 2
    glassSurface: Color(0xEEFAF8F5),   // 93% frosted linen overlay
    border: Color(0xFFE8E2D5),          // Gentle warm border
    cardBorder: Color(0xFFE8E2D5),
    primary: Color(0xFF047857),        // Deep calm emerald green
    onPrimary: Color(0xFFFFFFFF),      // Crisp white on primary
    secondary: Color(0xFF0D9488),      // Calming Teal
    gold: Color(0xFFB45309),           // Warm antique gold
    green: Color(0xFF15803D),          // Soothing Quranic leaf green
    red: Color(0xFFDC2626),            // Warm terracotta red (non-alarming)
    muted: Color(0xFF64748B),          // Slate-500 neutral muted
    currentWord: Color(0xFF0D9488),    // Calming teal active word highlight
    wordHighlight: Color(0xFF0D9488),  // Calming teal active word highlight
    text: Color(0xFF1E293B),           // Slate-800 deep charcoal (13:1 eye-gentle contrast)
    textSecondary: Color(0xFF475569),  // Slate-600 secondary text
    ayahOutline: Color(0x2EB45309),    // Soft warm amber outline (~18% alpha)
    ambientGlow: Color(0x18047857),    // Ambient soft emerald glow
    success: Color(0xFF15803D),        // Calm success green
    warning: Color(0xFFD97706),        // Warm honey warning
    error: Color(0xFFDC2626),          // Terracotta error
    info: Color(0xFF2563EB),           // Calming sapphire info
    cyan: Color(0xFF0D9488),           // Calm teal
    indigo: Color(0xFF4338CA),         // Royal Indigo
    emerald: Color(0xFF047857),        // Deep emerald
  );

  // ──────────────────────────────────────────────────────────────────────────
  // BLACK THEME — Deep OLED True Black (Tahajjud Eye Comfort)
  // True black foundation (#000000) for OLED battery, paired with soft
  // moonlit pearl text (#E2E8F0) to eliminate night glare & eye fatigue.
  // ──────────────────────────────────────────────────────────────────────────
  static const ThemeColors _blackColors = ThemeColors(
    bg: Color(0xFF000000),             // Pure OLED True Black
    surface: Color(0xFF0D0F14),        // Ultra-deep charcoal surface
    surfaceHigh: Color(0xFF151922),    // Elevation layer 1
    surfaceVariant: Color(0xFF1C222E), // Elevation layer 2
    glassSurface: Color(0xE005070A),   // 88% OLED glassmorphism
    border: Color(0xFF202736),          // Subtle boundary
    cardBorder: Color(0xFF202736),
    primary: Color(0xFF10B981),        // Serene Emerald
    onPrimary: Color(0xFF000000),
    secondary: Color(0xFF06B6D4),      // Cyan Spark
    gold: Color(0xFFEAB308),           // Luminous Amber Gold
    green: Color(0xFF22C55E),          // Calming leaf green
    red: Color(0xFFE06D63),            // Gentle rose terracotta
    muted: Color(0xFF64748B),          // Slate-500 neutral muted
    currentWord: Color(0xFF14B8A6),    // Calming luminous teal active word highlight
    wordHighlight: Color(0xFF14B8A6),  // Calming luminous teal active word highlight
    text: Color(0xFFE2E8F0),           // Moonlit pearl (halation-free)
    textSecondary: Color(0xFF94A3B8),  // Slate-400
    ayahOutline: Color(0x35EAB308),    // Soft amber outline
    ambientGlow: Color(0x2510B981),    // Gentle emerald glow
    success: Color(0xFF22C55E),
    warning: Color(0xFFF59E0B),
    error: Color(0xFFE06D63),
    info: Color(0xFF38BDF8),
    cyan: Color(0xFF06B6D4),
    indigo: Color(0xFF818CF8),
    emerald: Color(0xFF10B981),
  );

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      if (prefs.containsKey('lang')) {
        _lang = prefs.getString('lang') == 'en'
            ? AppLanguage.en
            : AppLanguage.ar;
      }
      if (prefs.containsKey('theme')) {
        final themeStr = prefs.getString('theme');
        try {
          _theme = AppTheme.values.firstWhere((t) => t.name == themeStr);
        } catch (_) {
          _theme = (themeStr == 'dark' || themeStr == 'oled' || themeStr == 'black')
              ? AppTheme.black
              : AppTheme.white;
        }
      } else {
        final brightness = WidgetsBinding.instance.platformDispatcher.platformBrightness;
        _theme = brightness == Brightness.dark ? AppTheme.black : AppTheme.white;
      }
      isBlurMode = prefs.getBool('blurMode') ?? false;
      // Mushaf layout bypassed: reset to false so no user is stuck in Mushaf mode
      isMushafLayout = false;
      if (prefs.containsKey('mushafLayout')) {
        await prefs.remove('mushafLayout');
      }

      autoScrollSpeed = prefs.getInt('autoScrollSpeed') ?? 2;
      hasChosenAutoScrollSpeed = prefs.getBool('has_chosen_speed') ?? false;
      
      if (prefs.containsKey('fontSize')) {
        fontSize = prefs.getDouble('fontSize') ?? 28.0;
      }
      
      tajweedClickCount = prefs.getInt('tajweed_click_count') ?? 0;
      // Migrate old boolean value if present
      if (tajweedClickCount == 0 && (prefs.getBool('has_clicked_tajweed_word') ?? false)) {
        tajweedClickCount = 10;
      }

      notifyListeners();
    } catch (e) {
      DebugLogger.logSimple('AppState', "Error loading settings: $e");
    }
  }
}

/// 2026 Design Token Palette used across the application.
///
/// Implements WCAG AA/AAA compliant Obsidian / Slate dark mode architecture,
/// clean spacious light mode, and vibrant 2026 accents (Emerald Glow, Cyan Spark, Electric Indigo).
class ThemeColors {
  final Color bg;
  final Color surface;
  final Color surfaceHigh;
  final Color surfaceVariant;
  final Color glassSurface;
  final Color border;
  final Color cardBorder;
  final Color primary;
  final Color onPrimary;
  final Color secondary;
  final Color gold;
  final Color green;
  final Color red;
  final Color muted;
  final Color currentWord;
  final Color wordHighlight;
  final Color text;
  final Color textSecondary;
  final Color ayahOutline;
  final Color ambientGlow;
  final Color success;
  final Color warning;
  final Color error;
  final Color info;
  final Color cyan;
  final Color indigo;
  final Color emerald;

  const ThemeColors({
    required this.bg,
    required this.surface,
    required this.surfaceHigh,
    required this.surfaceVariant,
    required this.glassSurface,
    required this.border,
    required this.cardBorder,
    required this.primary,
    required this.onPrimary,
    required this.secondary,
    required this.gold,
    required this.green,
    required this.red,
    required this.muted,
    required this.currentWord,
    required this.wordHighlight,
    required this.text,
    required this.textSecondary,
    required this.ayahOutline,
    required this.ambientGlow,
    required this.success,
    required this.warning,
    required this.error,
    required this.info,
    required this.cyan,
    required this.indigo,
    required this.emerald,
  });

  /// A faded version of gold for subtle backgrounds.
  Color get goldFade => gold.withValues(alpha: 0.25);
  
  /// A faded version of primary for subtle pill backgrounds.
  Color get primaryFade => primary.withValues(alpha: 0.12);
}
