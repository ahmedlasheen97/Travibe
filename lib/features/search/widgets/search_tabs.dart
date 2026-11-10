import 'package:flutter/material.dart';
import 'package:travibe/features/search/cubit/search_cubit.dart';

class SearchTabs extends StatelessWidget {
  final SearchTab selected;
  final ValueChanged<SearchTab> onSelected;

  const SearchTabs({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  static const _labels = {
    SearchTab.top: 'Top',
    SearchTab.recent: 'Recent',
    SearchTab.people: 'People',
  };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 20),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final tab in SearchTab.values)
              Padding(
                padding: EdgeInsets.only(
                  right: tab == SearchTab.values.last ? 0 : 28,
                ),
                child: _item(tab),
              ),
          ],
        ),
      ),
    );
  }

  Widget _item(SearchTab tab) {
    final isSelected = tab == selected;

    return InkWell(
      onTap: () => onSelected(tab),
      child: IntrinsicWidth(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _labels[tab]!,
              style: TextStyle(
                fontSize: 15,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color: isSelected ? Colors.white : Colors.white54,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              height: 2,
              color: isSelected ? Colors.white : Colors.transparent,
            ),
          ],
        ),
      ),
    );
  }
}
