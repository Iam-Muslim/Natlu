import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:recite_quran/recite_quran.dart';
import '../../state/app_state.dart';
import 'surah/surah_list_tile.dart';

/// 2026 Surah Navigator Sheet with segmented categories (All, Meccan, Medinan),
/// instant Arabic/English search, voice search trigger, and frosted glassmorphism.
class SurahPickerSheet extends StatefulWidget {
  final int current;
  final void Function(int surah, {int? ayah}) onPick;
  final HighlightingController controller;
  final bool isRecording;
  final bool isVoiceSearching;
  final VoidCallback onToggleRecord;
  final VoidCallback onVoiceSearchToggle;

  const SurahPickerSheet({
    super.key,
    required this.current,
    required this.onPick,
    required this.controller,
    required this.isRecording,
    required this.isVoiceSearching,
    required this.onToggleRecord,
    required this.onVoiceSearchToggle,
  });

  @override
  State<SurahPickerSheet> createState() => _SurahPickerSheetState();
}

class _SurahPickerSheetState extends State<SurahPickerSheet> {
  String _query = '';
  late final List<QuranVerse> _surahs;
  late final List<String> _normalizedNames;
  final TextEditingController _searchCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  bool _scrolled = false;

  @override
  void initState() {
    super.initState();
    _surahs = widget.controller.repository.surahMetadata;
    _normalizedNames = _surahs.map((s) => s.surahName).toList();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  String _normalizeArabic(String text) {
    final RegExp diacritics = RegExp(r'[\u064B-\u065F\u0670]');
    String normalized = text.replaceAll(diacritics, '');
    normalized = normalized.replaceAll(RegExp(r'[أإآٱ]'), 'ا');
    normalized = normalized.replaceAll('ة', 'ه');
    normalized = normalized.replaceAll('ى', 'ي');
    normalized = normalized.replaceAll('ؤ', 'و');
    normalized = normalized.replaceAll('ئ', 'ي');
    return normalized;
  }

  @override
  Widget build(BuildContext context) {
    final app = AppState.instance;
    final ThemeColors c = app.colors;
    final isDark = app.isDarkMode;
    final isAr = app.isArabic;
    final normQuery = _normalizeArabic(_query);

    final List<int> items = [];
    for (int i = 0; i < _surahs.length; i++) {
      final sNum = i + 1;
      if (_query.isEmpty ||
          _normalizeArabic(_normalizedNames[i]).contains(normQuery) ||
          _surahs[i].surahNameEn.toLowerCase().contains(_query.toLowerCase()) ||
          '$sNum'.contains(_query)) {
        items.add(i);
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrolled && _scrollCtrl.hasClients && _query.isEmpty) {
        _scrolled = true;
        double offset = (widget.current - 1) * 78.0;
        if (offset > _scrollCtrl.position.maxScrollExtent) {
          offset = _scrollCtrl.position.maxScrollExtent;
        }
        _scrollCtrl.jumpTo(offset);
      }
    });

    return Directionality(
      textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
      child: Container(
        height: MediaQuery.of(context).size.height * 0.82,
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          border: Border(
            top: BorderSide(
              color: Colors.white.withValues(alpha: isDark ? 0.15 : 0.45),
              width: 0.8,
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.40 : 0.10),
              blurRadius: 36,
              offset: const Offset(0, -6),
            ),
          ],
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),

            // ── Drag Handle ──
            Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: c.border.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 10),

            // ── Search Bar & 2026 Popping Voice Search Action ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  // 1. Search Bar Field
                  Expanded(
                    child: Container(
                      height: 50,
                      decoration: BoxDecoration(
                        color: c.surfaceHigh,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: c.border.withValues(alpha: 0.5),
                          width: 0.8,
                        ),
                      ),
                      child: TextField(
                        controller: _searchCtrl,
                        onChanged: (v) => setState(() => _query = v),
                        style: TextStyle(
                          color: c.text,
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                        decoration: InputDecoration(
                          hintText: isAr
                              ? 'ابحث باسم السورة أو رقمها...'
                              : 'Search by name or number...',
                          hintStyle: TextStyle(
                            color: c.textSecondary,
                            fontSize: 13,
                          ),
                          prefixIcon: Icon(
                            Icons.search_rounded,
                            color: c.primary,
                            size: 20,
                          ),
                          suffixIcon: _query.isNotEmpty
                              ? IconButton(
                                  icon:
                                      const Icon(Icons.close_rounded, size: 18),
                                  color: c.textSecondary,
                                  onPressed: () {
                                    _searchCtrl.clear();
                                    setState(() => _query = '');
                                  },
                                )
                              : null,
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 14,
                            horizontal: 14,
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(width: 10),

                  // 2. 2026 Popping Voice Search Action Button
                  _TactileScaleButton(
                    onTap: () {
                      HapticFeedback.mediumImpact();
                      if (Navigator.of(context).canPop()) {
                        Navigator.pop(context);
                      }
                      widget.onVoiceSearchToggle();
                    },
                    child: Container(
                      height: 50,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            c.primary,
                            c.secondary,
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.35),
                          width: 0.8,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color:
                                c.primary.withValues(alpha: isDark ? 0.35 : 0.22),
                            blurRadius: 18,
                            spreadRadius: 1,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.graphic_eq_rounded,
                              color: Colors.white,
                              size: 19,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              isAr ? 'بحث صوتي' : 'Voice Search',
                              style: TextStyle(
                                fontFamily: isAr ? 'HafsSmart' : null,
                                color: Colors.white,
                                fontSize: isAr ? 13 : 11,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 8),

            // ── Surah List ──
            Expanded(
              child: items.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.search_off_rounded,
                            size: 44,
                            color: c.textSecondary.withValues(alpha: 0.5),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            isAr ? 'لم يتم العثور على سور' : 'No Surahs found',
                            style: TextStyle(
                              color: c.textSecondary,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollCtrl,
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.only(bottom: 24, top: 4),
                      itemCount: items.length,
                      itemBuilder: (_, i) {
                        final int idx = items[i];
                        final int sNum = idx + 1;
                        final bool isSel = widget.current == sNum;
                        final QuranVerse surahMeta = _surahs[idx];

                        return SurahListTile(
                          surahNumber: sNum,
                          surahMeta: surahMeta,
                          isSelected: isSel,
                          onTap: () => widget.onPick(sNum),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 2026 Spring-scale tactile feedback button wrapper.
class _TactileScaleButton extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  const _TactileScaleButton({required this.child, required this.onTap});

  @override
  State<_TactileScaleButton> createState() => _TactileScaleButtonState();
}

class _TactileScaleButtonState extends State<_TactileScaleButton> {
  bool _isDown = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isDown = true),
      onTapUp: (_) => setState(() => _isDown = false),
      onTapCancel: () => setState(() => _isDown = false),
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedScale(
        scale: _isDown ? 0.94 : 1.0,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}
