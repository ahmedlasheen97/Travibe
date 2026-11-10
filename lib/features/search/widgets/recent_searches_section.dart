import 'package:flutter/material.dart';

class RecentSearchesSection extends StatelessWidget {
  final List<String> searches;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onRemove;
  final VoidCallback onClearAll;

  const RecentSearchesSection({
    super.key,
    required this.searches,
    required this.onSelect,
    required this.onRemove,
    required this.onClearAll,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Recent Searches',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
              ),
            ),
            InkWell(
              onTap: onClearAll,
              child: Text(
                'Clear All',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 14),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        for (final search in searches)
          InkWell(
            onTap: () => onSelect(search),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.schedule_rounded, color: Colors.white54, size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      search,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ),
                  InkWell(
                    onTap: () => onRemove(search),
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(Icons.close_rounded, color: Colors.white54, size: 22),
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