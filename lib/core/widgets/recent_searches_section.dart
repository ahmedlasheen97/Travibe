import 'package:flutter/material.dart';
import 'package:travibe/core/constants/app_sizes.dart';

/// "Recent Searches" header with Clear All and clock / label / X rows.
/// Renders nothing when [items] is empty.
class RecentSearchesSection<T> extends StatelessWidget {
  const RecentSearchesSection({
    super.key,
    required this.items,
    required this.labelOf,
    required this.onSelect,
    required this.onRemove,
    required this.onClearAll,
  });

  final List<T> items;
  final String Function(T item) labelOf;
  final ValueChanged<T> onSelect;
  final ValueChanged<T> onRemove;
  final VoidCallback onClearAll;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final muted = Colors.white.withValues(alpha: 0.6);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Recent Searches',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: AppSizes.sp18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            InkWell(
              key: const ValueKey('recent-searches-clear'),
              onTap: onClearAll,
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: AppSizes.ph4),
                child: Text(
                  'Clear All',
                  style: TextStyle(color: muted, fontSize: AppSizes.sp14),
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: AppSizes.h8),
        for (var i = 0; i < items.length; i++)
          InkWell(
            key: ValueKey('recent-search-$i'),
            onTap: () => onSelect(items[i]),
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: AppSizes.ph8),
              child: Row(
                children: [
                  Icon(
                    Icons.schedule_rounded,
                    color: muted,
                    size: AppSizes.sp22,
                  ),
                  SizedBox(width: AppSizes.w12),
                  Expanded(
                    child: Text(
                      labelOf(items[i]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: AppSizes.sp16,
                      ),
                    ),
                  ),
                  InkWell(
                    key: ValueKey('recent-search-remove-$i'),
                    onTap: () => onRemove(items[i]),
                    child: Padding(
                      padding: EdgeInsets.all(AppSizes.pw6),
                      child: Icon(
                        Icons.close_rounded,
                        color: muted,
                        size: AppSizes.sp22,
                        semanticLabel: 'Remove ${labelOf(items[i])}',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
