import 'package:flutter/material.dart';
import '../../../state/app_state.dart';

/// Thin separator line between settings.
class SettingDivider extends StatelessWidget {
  final ThemeColors c;
  const SettingDivider({super.key, required this.c});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      color: c.border.withValues(alpha: 0.2),
    );
  }
}

/// A single setting row with icon, title, and control widget.
class SettingTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final ThemeColors c;
  final Widget child;

  const SettingTile({
    super.key,
    required this.icon,
    required this.title,
    required this.c,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Icon(icon, color: c.gold, size: 20),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: Text(
              title,
              style: TextStyle(
                color: c.text,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(flex: 3, child: child),
        ],
      ),
    );
  }
}

/// Modern pill-shaped segmented selector.
class PillSelector extends StatelessWidget {
  final List<String> labels;
  final int selected;
  final ThemeColors c;
  final ValueChanged<int> onSelected;

  const PillSelector({
    super.key,
    required this.labels,
    required this.selected,
    required this.c,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: c.bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.border.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: List.generate(labels.length, (i) {
          final isSel = i == selected;
          return Expanded(
            child: GestureDetector(
              onTap: () => onSelected(i),
              behavior: HitTestBehavior.opaque,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: isSel ? c.gold : Colors.transparent,
                  borderRadius: BorderRadius.circular(11),
                  boxShadow: isSel
                      ? [
                          BoxShadow(
                            color: c.gold.withValues(alpha: 0.25),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : [],
                ),
                child: Center(
                  child: Text(
                    labels[i],
                    style: TextStyle(
                      color: isSel
                          ? Colors.white
                          : c.text.withValues(alpha: 0.65),
                      fontSize: 13,
                      fontWeight: isSel ? FontWeight.w700 : FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
