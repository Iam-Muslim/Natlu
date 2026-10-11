import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:recite_quran/recite_quran.dart';
import '../../../state/app_state.dart';

/// Production-ready Voice Search modal dialog for reciting any Ayah across the Quran.
///
/// Features:
/// - Prominent HafsSmart instruction directing the user to recite aloud.
/// - Pulsing microphone and animated rhythmic soundwave visualizer.
/// - Balanced dynamic grace countdown (3s-7s based on candidate count).
/// - One-tap Hold / Resume toggle to freeze countdown and browse at leisure.
/// - Instant 0ms navigation on unique match or direct candidate card tap.
/// - Zero raw phonemes or ASR tokens rendered in the UI.
class VoiceSearchDialog extends StatefulWidget {
  final VoidCallback onStop;
  final ValueListenable<bool>? isLoading;
  final ValueListenable<String>? asrTextNotifier;
  final ValueListenable<VoiceSearchResult?>? searchResultNotifier;
  final void Function(int surah, int ayah)? onSelectCandidate;

  const VoiceSearchDialog({
    super.key,
    required this.onStop,
    this.isLoading,
    this.asrTextNotifier,
    this.searchResultNotifier,
    this.onSelectCandidate,
  });

  /// Displays the VoiceSearchDialog modal.
  static void show(
    BuildContext context, {
    required VoidCallback onStop,
    ValueListenable<bool>? isLoading,
    ValueListenable<String>? asrTextNotifier,
    ValueListenable<VoiceSearchResult?>? searchResultNotifier,
    void Function(int surah, int ayah)? onSelectCandidate,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (_) => VoiceSearchDialog(
        onStop: onStop,
        isLoading: isLoading,
        asrTextNotifier: asrTextNotifier,
        searchResultNotifier: searchResultNotifier,
        onSelectCandidate: onSelectCandidate,
      ),
    );
  }

  @override
  State<VoiceSearchDialog> createState() => _VoiceSearchDialogState();
}

class _VoiceSearchDialogState extends State<VoiceSearchDialog>
    with TickerProviderStateMixin {
  late final AnimationController _pulseCtrl;
  late final AnimationController _countdownCtrl;

  VoiceSearchResult? _currentResult;
  bool _hasSelected = false;
  bool _isCountdownPaused = false;
  int _activeGraceSeconds = 4;

  /// Balanced grace countdown duration based on the number of candidate Ayahs:
  /// - 1 Ayah: 3s
  /// - 2 Ayahs: 4s
  /// - 3 Ayahs: 5s
  /// - 4 Ayahs: 6s
  /// - 5+ Ayahs: 7s
  int _calculateGraceSeconds(int count) {
    if (count <= 1) return 3;
    if (count == 2) return 4;
    if (count == 3) return 5;
    if (count == 4) return 6;
    return 7;
  }

  @override
  void initState() {
    super.initState();

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _activeGraceSeconds = _calculateGraceSeconds(
      widget.searchResultNotifier?.value?.candidates.length ?? 2,
    );

    _countdownCtrl = AnimationController(
      vsync: this,
      duration: Duration(seconds: _activeGraceSeconds),
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          _autoNavigateToTopMatch();
        }
      });

    _currentResult = widget.searchResultNotifier?.value;
    widget.searchResultNotifier?.addListener(_onSearchResultChanged);

    if (_currentResult != null && _currentResult!.candidates.isNotEmpty) {
      if (_currentResult!.isUnique && _currentResult!.topMatch != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_hasSelected) {
            _selectCandidate(
              _currentResult!.topMatch!.surah,
              _currentResult!.topMatch!.ayah,
            );
          }
        });
      } else {
        _startCountdown();
      }
    }
  }

  @override
  void dispose() {
    widget.searchResultNotifier?.removeListener(_onSearchResultChanged);
    _pulseCtrl.dispose();
    _countdownCtrl.dispose();
    super.dispose();
  }

  void _onSearchResultChanged() {
    if (!mounted || _hasSelected) return;
    final res = widget.searchResultNotifier?.value;
    setState(() => _currentResult = res);

    if (res != null && res.candidates.isNotEmpty) {
      // Unique match navigates instantly unless user explicitly paused
      if (res.isUnique && res.topMatch != null && !_isCountdownPaused) {
        _selectCandidate(res.topMatch!.surah, res.topMatch!.ayah);
        return;
      }
      if (!_isCountdownPaused) {
        _startCountdown();
      }
    } else {
      _countdownCtrl.stop();
      _countdownCtrl.reset();
      _isCountdownPaused = false;
    }
  }

  void _startCountdown() {
    if (_isCountdownPaused) return;

    final int count = _currentResult?.candidates.length ?? 1;
    final int targetSeconds = _calculateGraceSeconds(count);

    if (_countdownCtrl.isAnimating) {
      if (targetSeconds > _activeGraceSeconds) {
        _activeGraceSeconds = targetSeconds;
        _countdownCtrl.duration = Duration(seconds: targetSeconds);
      }
      return;
    }

    _activeGraceSeconds = targetSeconds;
    _countdownCtrl.duration = Duration(seconds: targetSeconds);
    _countdownCtrl.forward(from: 0.0);
  }

  void _togglePauseCountdown() {
    if (!mounted || _hasSelected) return;
    setState(() {
      _isCountdownPaused = !_isCountdownPaused;
      if (_isCountdownPaused) {
        _countdownCtrl.stop();
      } else {
        if (_countdownCtrl.value < 1.0) {
          _countdownCtrl.forward();
        } else {
          _autoNavigateToTopMatch();
        }
      }
    });
  }

  void _autoNavigateToTopMatch() {
    if (!mounted || _hasSelected || _isCountdownPaused) return;
    final top = _currentResult?.topMatch ?? _currentResult?.candidates.firstOrNull;
    if (top != null) {
      _selectCandidate(top.surah, top.ayah);
    }
  }

  void _selectCandidate(int surah, int ayah) {
    if (_hasSelected) return;
    _hasSelected = true;
    _countdownCtrl.stop();
    if (Navigator.of(context, rootNavigator: true).canPop()) {
      Navigator.of(context, rootNavigator: true).pop();
    }
    widget.onSelectCandidate?.call(surah, ayah);
  }

  void _cancelSearch() {
    if (_hasSelected) return;
    _hasSelected = true;
    _countdownCtrl.stop();
    if (Navigator.of(context, rootNavigator: true).canPop()) {
      Navigator.of(context, rootNavigator: true).pop();
    }
    widget.onStop();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppState.instance;
    final c = app.colors;
    final isAr = app.isArabic;
    final media = MediaQuery.of(context);

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Container(
        constraints: BoxConstraints(
          maxWidth: 480,
          maxHeight: media.size.height * 0.82,
        ),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: c.gold.withValues(alpha: 0.28), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.45),
              blurRadius: 36,
              spreadRadius: 2,
              offset: const Offset(0, 10),
            ),
            BoxShadow(
              color: c.gold.withValues(alpha: 0.08),
              blurRadius: 24,
            ),
          ],
        ),
        child: Directionality(
          textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
            child: widget.isLoading != null
                ? ValueListenableBuilder<bool>(
                    valueListenable: widget.isLoading!,
                    builder: (_, loading, __) =>
                        loading ? _buildLoadingState(c, isAr) : _buildContent(c, isAr),
                  )
                : _buildContent(c, isAr),
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingState(ThemeColors c, bool isAr) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 38,
            height: 38,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              valueColor: AlwaysStoppedAnimation<Color>(c.gold),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            isAr ? 'جاري تجهيز البحث الصوتي...' : 'Preparing voice search index...',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: c.text,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(ThemeColors c, bool isAr) {
    final bool hasCandidates =
        _currentResult != null && _currentResult!.candidates.isNotEmpty;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Top Close Button ──
        Align(
          alignment: AlignmentDirectional.topEnd,
          child: IconButton(
            icon: Icon(Icons.close_rounded, color: c.muted, size: 22),
            tooltip: isAr ? 'إلغاء' : 'Cancel',
            onPressed: _cancelSearch,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ),
        const SizedBox(height: 12),

        // ── Hero Section (Listening or Candidates) ──
        if (!hasCandidates) ...[
          const SizedBox(height: 8),
          _buildHeroListening(c, isAr),
          const SizedBox(height: 8),
        ] else ...[
          _buildCompactHeader(c, isAr),
          const SizedBox(height: 12),
          _buildCountdownGraceBanner(c, isAr),
          const SizedBox(height: 10),
          _buildCandidatesList(c, isAr),
          const SizedBox(height: 8),
        ],

        // ── Bottom Action ──
        Center(
          child: TextButton.icon(
            onPressed: _cancelSearch,
            icon: Icon(Icons.close_rounded, size: 16, color: c.muted),
            label: Text(
              isAr ? 'إلغاء البحث' : 'Cancel Search',
              style: TextStyle(color: c.muted, fontSize: 13),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeroListening(ThemeColors c, bool isAr) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Pulsing Microphone with concentric rings
        AnimatedBuilder(
          animation: _pulseCtrl,
          builder: (_, __) {
            final val = _pulseCtrl.value;
            return Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 88 + (val * 12),
                  height: 88 + (val * 12),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: c.gold.withValues(alpha: 0.06 * (1.0 - val)),
                  ),
                ),
                Container(
                  width: 76 + (val * 6),
                  height: 76 + (val * 6),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: c.gold.withValues(alpha: 0.12),
                  ),
                ),
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [
                        c.gold.withValues(alpha: 0.28),
                        c.gold.withValues(alpha: 0.12),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    border: Border.all(
                      color: c.gold.withValues(alpha: 0.45),
                      width: 1.5,
                    ),
                  ),
                  child: Icon(Icons.mic_rounded, color: c.gold, size: 28),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 18),

        // Animated soundwave bars
        _buildWaveBars(count: 7, baseHeight: 8, maxHeight: 26, c: c),
        const SizedBox(height: 20),

        // Primary prompt
        Text(
          isAr
              ? 'اتلُ أي آية من القرآن العظيم'
              : 'Recite any verse from The Great Quran',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: isAr ? 'HafsSmart' : null,
            color: c.text,
            fontSize: isAr ? 21 : 17,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6),

        // Subtitle instruction
        Text(
          isAr
              ? 'اقرأ بصوتك للبحث الفوري في كامل المصحف'
              : 'Recite aloud to search instantly across the Quran',
          textAlign: TextAlign.center,
          style: TextStyle(color: c.muted, fontSize: 12.5),
        ),
        const SizedBox(height: 14),

        // Status badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: c.gold.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: c.gold.withValues(alpha: 0.2)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(color: c.gold, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Text(
                isAr ? 'في انتظار تلاوتك...' : 'Listening to recitation...',
                style: TextStyle(
                  color: c.gold,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCompactHeader(ThemeColors c, bool isAr) {
    return Row(
      children: [
        Expanded(
          child: Text(
            isAr ? 'الآيات المتطابقة' : 'Matching Ayahs',
            style: TextStyle(
              color: c.gold,
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        _buildWaveBars(count: 4, baseHeight: 6, maxHeight: 16, c: c),
      ],
    );
  }

  /// Reusable soundwave equalizer visualizer.
  Widget _buildWaveBars({
    required int count,
    required double baseHeight,
    required double maxHeight,
    required ThemeColors c,
  }) {
    return AnimatedBuilder(
      animation: _pulseCtrl,
      builder: (_, __) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(count, (i) {
            final h = baseHeight +
                (maxHeight - baseHeight) *
                    math.sin((_pulseCtrl.value * math.pi) + (i * 0.7)).abs();
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 2),
              width: 3,
              height: h,
              decoration: BoxDecoration(
                color: c.gold.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(2),
              ),
            );
          }),
        );
      },
    );
  }

  Widget _buildCountdownGraceBanner(ThemeColors c, bool isAr) {
    return Container(
      decoration: BoxDecoration(
        color: _isCountdownPaused
            ? c.surfaceHigh.withValues(alpha: 0.5)
            : c.gold.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _isCountdownPaused
              ? c.border.withValues(alpha: 0.3)
              : c.gold.withValues(alpha: 0.22),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            child: Row(
              children: [
                Icon(
                  _isCountdownPaused
                      ? Icons.pause_circle_outline_rounded
                      : Icons.timer_outlined,
                  size: 16,
                  color: _isCountdownPaused ? c.muted : c.gold,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: AnimatedBuilder(
                    animation: _countdownCtrl,
                    builder: (_, __) {
                      if (_isCountdownPaused) {
                        return Text(
                          isAr
                              ? 'تم إيقاف المؤقت • تصفح واختر الآية'
                              : 'Countdown paused • Select an Ayah',
                          style: TextStyle(
                            color: c.text.withValues(alpha: 0.9),
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                          ),
                        );
                      }
                      final int secRemaining =
                          ((1.0 - _countdownCtrl.value) * _activeGraceSeconds)
                              .ceil()
                              .clamp(1, _activeGraceSeconds);
                      return Text(
                        isAr
                            ? 'الانتقال لأقرب تطابق خلال $secRemaining ثوانٍ'
                            : 'Auto-jumping to top match in ${secRemaining}s',
                        style: TextStyle(
                          color: c.gold,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 6),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _togglePauseCountdown,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3.5,
                      ),
                      decoration: BoxDecoration(
                        color: _isCountdownPaused
                            ? c.green.withValues(alpha: 0.14)
                            : c.gold.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _isCountdownPaused
                              ? c.green.withValues(alpha: 0.3)
                              : c.gold.withValues(alpha: 0.28),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _isCountdownPaused
                                ? Icons.play_arrow_rounded
                                : Icons.pause_rounded,
                            size: 13,
                            color: _isCountdownPaused ? c.green : c.gold,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            _isCountdownPaused
                                ? (isAr ? 'استئناف' : 'Resume')
                                : (isAr ? 'إيقاف' : 'Hold'),
                            style: TextStyle(
                              color: _isCountdownPaused ? c.green : c.gold,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
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
          AnimatedBuilder(
            animation: _countdownCtrl,
            builder: (_, __) {
              return ClipRRect(
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(13)),
                child: LinearProgressIndicator(
                  value: (1.0 - _countdownCtrl.value).clamp(0.0, 1.0),
                  minHeight: 3,
                  backgroundColor: _isCountdownPaused
                      ? c.border.withValues(alpha: 0.15)
                      : c.gold.withValues(alpha: 0.12),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    _isCountdownPaused ? c.muted : c.gold,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCandidatesList(ThemeColors c, bool isAr) {
    final candidates = _currentResult!.candidates;

    return Flexible(
      child: ListView.separated(
        physics: const BouncingScrollPhysics(),
        shrinkWrap: true,
        itemCount: candidates.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final match = candidates[index];
          return _buildCandidateCard(
            context,
            match: match,
            isTop: index == 0,
            c: c,
            isAr: isAr,
          );
        },
      ),
    );
  }

  Widget _buildCandidateCard(
    BuildContext context, {
    required AyahSearchMatch match,
    required bool isTop,
    required ThemeColors c,
    required bool isAr,
  }) {
    final percentage = (match.score * 100).toInt().clamp(0, 100);
    final surahTitle = isAr
        ? (match.surahNameAr ?? 'سورة ${match.surah}')
        : (match.surahNameEn ?? 'Surah ${match.surah}');

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _selectCandidate(match.surah, match.ayah),
        borderRadius: BorderRadius.circular(16),
        hoverColor: c.gold.withValues(alpha: 0.08),
        splashColor: c.gold.withValues(alpha: 0.15),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: isTop
                ? c.surfaceHigh.withValues(alpha: 0.6)
                : c.bg.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isTop
                  ? c.gold.withValues(alpha: 0.38)
                  : c.border.withValues(alpha: 0.25),
              width: isTop ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(
                    surahTitle,
                    style: TextStyle(
                      fontFamily: isAr ? 'HafsSmart' : null,
                      fontWeight: FontWeight.bold,
                      fontSize: isAr ? 16 : 14,
                      color: c.gold,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: c.gold.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      isAr ? 'آية ${match.ayah}' : 'Ayah ${match.ayah}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: c.gold,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: percentage >= 85
                          ? c.green.withValues(alpha: 0.16)
                          : c.gold.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$percentage%',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: percentage >= 85 ? c.green : c.gold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    isAr
                        ? Icons.arrow_back_ios_new_rounded
                        : Icons.arrow_forward_ios_rounded,
                    size: 12,
                    color: c.muted.withValues(alpha: 0.6),
                  ),
                ],
              ),
              if (match.textUthmani != null && match.textUthmani!.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  match.textUthmani!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textDirection: TextDirection.rtl,
                  style: TextStyle(
                    fontFamily: 'HafsSmart',
                    fontSize: 16.5,
                    height: 1.5,
                    color: c.text.withValues(alpha: 0.88),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
