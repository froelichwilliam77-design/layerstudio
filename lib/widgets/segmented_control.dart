import 'package:flutter/material.dart';

import '../theme/studio_theme.dart';

/// Modern single-row segmented control.
/// Active state = filled accent + high-contrast text (no checkmark icons).
class StudioSegmentedControl<T> extends StatelessWidget {
  const StudioSegmentedControl({
    super.key,
    required this.segments,
    required this.value,
    required this.onChanged,
    this.accent,
    this.height = 36,
  });

  final List<StudioSegment<T>> segments;
  final T value;
  final ValueChanged<T> onChanged;
  final Color? accent;
  final double height;

  @override
  Widget build(BuildContext context) {
    final accentColor = accent ?? StudioColors.accent;
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: StudioColors.surface2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: StudioColors.border),
      ),
      padding: const EdgeInsets.all(2),
      child: Row(
        children: [
          for (var i = 0; i < segments.length; i++) ...[
            if (i > 0) const SizedBox(width: 2),
            Expanded(
              child: _Seg(
                label: segments[i].label,
                selected: segments[i].value == value,
                accent: accentColor,
                onTap: () => onChanged(segments[i].value),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class StudioSegment<T> {
  const StudioSegment({required this.value, required this.label});
  final T value;
  final String label;
}

class _Seg extends StatelessWidget {
  const _Seg({
    required this.label,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? accent : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Center(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              color: selected ? StudioColors.bg : StudioColors.textDim,
              letterSpacing: 0.1,
            ),
          ),
        ),
      ),
    );
  }
}
