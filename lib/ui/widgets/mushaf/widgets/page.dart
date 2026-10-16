import 'package:flutter/material.dart' hide Page;
import 'package:recite_quran/recite_quran.dart';

import '../../../../state/app_state.dart';
import '../classes/line.dart';
import '../services/mushaf_provider.dart';
import 'line.dart';

/// ============================================================================
/// CRITICAL LAYOUT ENGINE: [PageWidget]
/// ============================================================================
/// ARCHITECTURAL RULES & INVARIANTS — DO NOT ALTER WITHOUT READING:
///
/// 1. UNIFIED 15-SLOT MEDINA GRID & SURAH BANNER ALIGNMENT (PAGES 3..604):
///    - Standard Medina Mushaf pages strictly follow a 15-line grid.
///    - Container height is unified to `linesContainerHeight = lineSlotHeight * 15`.
///    - In pages where BasmalaLine is embedded into the Surah header banner (14 visible lines),
///      the banner and text lines occupy Slots 0..13, and a trailing Spacer(flex: 1) absorbs
///      the bottom slot.
///    - This guarantees that Slot 0 (the Surah banner) starts at the EXACT same horizontal baseline
///      as Slot 0 (first Ayah) of adjacent pages, and stretches up in complete lockstep!
///
/// 2. BISMILLAH EMBEDDED IN SURAH HEADER (NO STANDALONE BASMALA LINE):
///    - [BasmalaLine] is deliberately SKIPPED in `flexChildren` (`if (line is BasmalaLine) continue;`).
///    - Bismillah is embedded directly inside the Surah banner on the left (RTL end).
///    - DO NOT render a standalone BasmalaLine or allocate a flex slot for it, as this
///      would duplicate Bismillah and steal vertical height from text lines.
///
/// 3. DISPLAY CLEARANCE & BEZEL SAFETY (`maxWidth - 36.0`):
///    - `lineWidth` is set to `(maxWidth - 36.0)` providing 18.0px horizontal clearance on each side.
///    - Prevents text and Ayah markers from colliding with curved glass edges, black bezels,
///      or screen margins on Android displays.
///
/// 4. BOTTOM-LEFT PAGE NUMBER SEPARATION:
///    - The bottom page number label is rendered by the outer [MushafView] Stack
///      outside the page's layout constraints.
///    - DO NOT embed the page number inside [PageWidget]'s column, as that would steal
///      vertical height from the 15 Quranic lines.
///
/// 5. SPECIAL CENTERING FOR PAGES 1 & 2:
///    - Pages 1 (Al-Fatiha) and 2 (Al-Baqarah 1-5) have fewer lines and use symmetric
///      top & bottom Spacers for Quranic decorative centering.
/// ============================================================================
class PageWidget extends StatefulWidget {
  final int pageNumber;
  final HighlightingController controller;
  final bool isRecording;
  final bool isAutoScrolling;
  final String wordFontFamily;
  final bool showBottomPageNumber;
  final VoidCallback onStateChangeRequested;

  const PageWidget({
    super.key,
    required this.pageNumber,
    required this.controller,
    required this.isRecording,
    required this.isAutoScrolling,
    this.wordFontFamily = 'HafsSmart',
    this.showBottomPageNumber = true,
    required this.onStateChangeRequested,
  });

  @override
  State<PageWidget> createState() => _PageWidgetState();
}

class _PageWidgetState extends State<PageWidget>
    with AutomaticKeepAliveClientMixin<PageWidget> {
  @override
  bool get wantKeepAlive => true;

  bool _wasAudioOnThisPage = false;
  bool _wasControllerOnThisPage = false;

  @override
  void initState() {
    super.initState();
    _attachListeners();
  }

  @override
  void didUpdateWidget(PageWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.activeAyah.removeListener(_onControllerAyahChanged);
      oldWidget.controller.globalRevision.removeListener(_onVisualStateChanged);
      oldWidget.controller.removeListener(_onControllerUpdate);
      widget.controller.activeAyah.addListener(_onControllerAyahChanged);
      widget.controller.globalRevision.addListener(_onVisualStateChanged);
      widget.controller.addListener(_onControllerUpdate);
    }
    if (oldWidget.isRecording != widget.isRecording ||
        oldWidget.isAutoScrolling != widget.isAutoScrolling) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _detachListeners();
    super.dispose();
  }

  void _attachListeners() {
    final app = AppState.instance;
    app.activeAudioWordIndex.addListener(_onAudioWordChanged);
    app.activeAudioAyah.addListener(_onAudioAyahChanged);
    app.activeAudioSurah.addListener(_onAudioAyahChanged);
    app.isAudioPlaying.addListener(_onAudioStateChanged);
    app.isAudioBuffering.addListener(_onAudioStateChanged);
    app.blurModeNotifier.addListener(_onVisualStateChanged);
    widget.controller.activeAyah.addListener(_onControllerAyahChanged);
    widget.controller.globalRevision.addListener(_onVisualStateChanged);
    widget.controller.addListener(_onControllerUpdate);
  }

  void _detachListeners() {
    final app = AppState.instance;
    app.activeAudioWordIndex.removeListener(_onAudioWordChanged);
    app.activeAudioAyah.removeListener(_onAudioAyahChanged);
    app.activeAudioSurah.removeListener(_onAudioAyahChanged);
    app.isAudioPlaying.removeListener(_onAudioStateChanged);
    app.isAudioBuffering.removeListener(_onAudioStateChanged);
    app.blurModeNotifier.removeListener(_onVisualStateChanged);
    widget.controller.activeAyah.removeListener(_onControllerAyahChanged);
    widget.controller.globalRevision.removeListener(_onVisualStateChanged);
    widget.controller.removeListener(_onControllerUpdate);
  }

  bool _pageContainsAyah(int? surah, int? ayah) {
    if (surah == null || ayah == null) return false;
    final provider = MushafProvider.instance;
    final page = provider.getPage(widget.pageNumber);
    return page?.ayahKeys.contains('$surah:$ayah') ?? false;
  }

  void _onControllerUpdate() {
    if (!mounted) return;
    if (!widget.isRecording) return;
    final currentMatched = widget.controller.currentMatchedVerse?.verse;
    final int surah = currentMatched?.surah ??
        (widget.controller.targetSurah != 0
            ? widget.controller.targetSurah
            : AppState.instance.lastSurah);
    final int? ayah = currentMatched?.ayah ?? widget.controller.activeAyah.value;
    final bool isNowOnThisPage = _pageContainsAyah(surah, ayah);
    if (isNowOnThisPage || _wasControllerOnThisPage) {
      _wasControllerOnThisPage = isNowOnThisPage;
      setState(() {});
    }
  }

  void _onAudioWordChanged() {
    final app = AppState.instance;
    final s = app.activeAudioSurah.value;
    final a = app.activeAudioAyah.value;
    if (_pageContainsAyah(s, a)) {
      if (mounted) setState(() {});
    }
  }

  void _onAudioAyahChanged() {
    final app = AppState.instance;
    final s = app.activeAudioSurah.value;
    final a = app.activeAudioAyah.value;
    final bool isNowOnThisPage = _pageContainsAyah(s, a);
    if (isNowOnThisPage || _wasAudioOnThisPage) {
      _wasAudioOnThisPage = isNowOnThisPage;
      if (mounted) setState(() {});
    }
  }

  void _onAudioStateChanged() {
    final app = AppState.instance;
    final s = app.activeAudioSurah.value;
    final a = app.activeAudioAyah.value;
    final bool isNowOnThisPage = _pageContainsAyah(s, a);
    if (isNowOnThisPage || _wasAudioOnThisPage) {
      _wasAudioOnThisPage = isNowOnThisPage;
      if (mounted) setState(() {});
    }
  }

  void _onControllerAyahChanged() {
    final activeAyah = widget.controller.activeAyah.value;
    final targetSurah = widget.controller.targetSurah != 0
        ? widget.controller.targetSurah
        : AppState.instance.lastSurah;
    final bool isNowOnThisPage = _pageContainsAyah(targetSurah, activeAyah);
    if (isNowOnThisPage || _wasControllerOnThisPage) {
      _wasControllerOnThisPage = isNowOnThisPage;
      if (mounted) setState(() {});
    }
  }

  void _onVisualStateChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final provider = MushafProvider.instance;
    final page = provider.getPage(widget.pageNumber);
    final app = AppState.instance;
    final colors = app.colors;

    if (page == null) {
      return const Center(child: CircularProgressIndicator.adaptive());
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final double maxWidth = constraints.maxWidth;
        final double maxHeight = constraints.maxHeight;

        final allLines = page.lines;

        // ======================================================================
        // ARCHITECTURAL INVARIANT: UNIFIED 15-SLOT MEDINA GRID & VERTICAL ALIGNMENT
        // ======================================================================
        // In the Medina Mushaf, the page layout is strictly a 15-line grid.
        // To guarantee that the top line (whether a Surah banner or first Ayah)
        // is at the EXACT same horizontal baseline across adjacent pages, and to
        // ensure that when stretching during recording the banner moves UP in lockstep
        // with pages having no banner (never lagging or positioned down):
        //
        // 1. All regular pages (3..604) use a unified 15-slot grid height:
        //    lineSlotHeight = (maxHeight / 15).clamp(30.0, 40.0)
        //    linesContainerHeight = lineSlotHeight * 15
        //
        // 2. In pages where BasmalaLine is embedded into the Surah header banner
        //    (resulting in 14 flexChildren), children occupy Slots 0..13, and a
        //    trailing Spacer(flex: 15 - flexCount) absorbs the bottom slot.
        //    This locks Slot 0, Slot 1, ... to identical vertical coordinates across
        //    all pages, so the Surah banner is at the EXACT same horizontal level
        //    as the first ayah of the next page!
        // ======================================================================
        const double maxComfortableSlotHeight = 40.0;
        final double lineSlotHeight =
            (maxHeight / 15).clamp(30.0, maxComfortableSlotHeight);
        final double linesContainerHeight = lineSlotHeight * 15;

        // ======================================================================
        // ARCHITECTURAL INVARIANT: ANDROID BEZEL & DISPLAY LINE CLEARANCE
        // ======================================================================
        // Mobile screens (especially Android AMOLED displays) have thin black
        // bezel borders and curved edge lines. We provide 18.0px margin on each
        // side (maxWidth - 36.0) so Quranic text never touches or clips the edge!
        // ======================================================================
        final double lineWidth = (maxWidth - 36.0).clamp(240.0, maxWidth);

        // Calibrated base font size: 17.2 to 18.8 based on screen width
        final double baseFontSize = ((lineWidth - 10.0) / 18.5).clamp(17.2, 18.8);

        final List<Widget> flexChildren = [];
        int flexCount = 0;

        for (int index = 0; index < allLines.length; index++) {
          final line = allLines[index];

          // CRITICAL INVARIANT: Bismillah is now embedded inside the Surah header on the left.
          // Omit redundant BasmalaLine so it does not consume a vertical line slot or duplicate Bismillah!
          if (line is BasmalaLine) {
            continue;
          }
          final nextLine = index + 1 < allLines.length ? allLines[index + 1] : null;

          flexChildren.add(
            Expanded(
              child: Center(
                child: LineWidget(
                  line: line,
                  nextLine: nextLine,
                  pageNumber: widget.pageNumber,
                  lineIndex: index,
                  lineWidth: lineWidth,
                  lineHeight: lineSlotHeight,
                  fontSize: baseFontSize,
                  wordFontFamily: widget.wordFontFamily,
                  colors: colors,
                  app: app,
                  controller: widget.controller,
                  isRecording: widget.isRecording,
                  isAutoScrolling: widget.isAutoScrolling,
                  onAyahSelected: widget.onStateChangeRequested,
                ),
              ),
            ),
          );
          flexCount++;
        }

        final List<Widget> columnChildren = [];

        // CRITICAL INVARIANT: Page vertical distribution
        if (widget.pageNumber <= 2) {
          // Special Quranic centering for Page 1 & 2 (Fatiha & Baqarah opening)
          final int emptyFlex = (15 - flexCount).clamp(0, 15);
          final int topEmpty = emptyFlex ~/ 2;
          final int bottomEmpty = emptyFlex - topEmpty;
          if (topEmpty > 0) columnChildren.add(Spacer(flex: topEmpty));
          columnChildren.addAll(flexChildren);
          if (bottomEmpty > 0) columnChildren.add(Spacer(flex: bottomEmpty));
        } else if (widget.pageNumber == 604) {
          // Page 604 contains 3 short surahs (Al-Ikhlas, Al-Falaq, An-Nas) at the end of the Quran
          columnChildren.addAll(flexChildren);
          if (flexCount < 15) {
            columnChildren.add(Spacer(flex: 15 - flexCount));
          }
        } else {
          // CRITICAL INVARIANT: All regular pages (3..603):
          // Lines stretch down 100% touching the bottom boundary with NO trailing Spacer!
          // Every page starts at the exact same top horizontal line (Y=0) and reaches the
          // exact same bottom horizontal line (Y=linesContainerHeight) with no page ending early!
          columnChildren.addAll(flexChildren);
        }

        return Directionality(
          textDirection: TextDirection.rtl,
          child: Center(
            child: SizedBox(
              width: lineWidth,
              height: linesContainerHeight,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: columnChildren,
              ),
            ),
          ),
        );
      },
    );
  }
}
