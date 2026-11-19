import 'package:flutter/widgets.dart';

/// A [SliverList] that builds its items only as they scroll into view:
/// [leading] widgets, then one item per id in [ids], then [trailing].
///
/// Each item is keyed `ValueKey('$keyPrefix$id')`, and the delegate finds
/// items by that key, so a card keeps its state (carousel page, expanded
/// caption) when posts are added, removed or reordered.
class LazyKeyedSliverList extends StatelessWidget {
  const LazyKeyedSliverList({
    super.key,
    required this.ids,
    required this.keyPrefix,
    required this.itemBuilder,
    this.leading = const [],
    this.trailing = const [],
  });

  final List<String> ids;
  final String keyPrefix;
  final Widget Function(BuildContext context, String id) itemBuilder;
  final List<Widget> leading;
  final List<Widget> trailing;

  ValueKey<String> keyOf(String id) => ValueKey('$keyPrefix$id');

  @override
  Widget build(BuildContext context) {
    final indexes = <String, int>{
      for (final (i, id) in ids.indexed) '$keyPrefix$id': leading.length + i,
    };
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          if (index < leading.length) return leading[index];
          final item = index - leading.length;
          if (item < ids.length) {
            final id = ids[item];
            return KeyedSubtree(
              key: keyOf(id),
              child: itemBuilder(context, id),
            );
          }
          return trailing[item - ids.length];
        },
        childCount: leading.length + ids.length + trailing.length,
        findChildIndexCallback: (key) =>
            key is ValueKey<String> ? indexes[key.value] : null,
      ),
    );
  }
}
