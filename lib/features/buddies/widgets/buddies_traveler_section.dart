import 'package:flutter/material.dart';
import 'package:travibe/features/buddies/data/buddies_landing_data.dart';
import 'package:travibe/features/buddies/widgets/buddies_traveler_card.dart';

class BuddiesSectionHeader extends StatelessWidget {
  const BuddiesSectionHeader({super.key, required this.title, this.onSeeAll});
  final String title;
  final VoidCallback? onSeeAll;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 28),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                letterSpacing: 0,
                color: Colors.white,
                fontSize: 18,
                height: 24 / 18,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: constraints.maxWidth * .4),
            child: Tooltip(
              message: onSeeAll == null
                  ? 'See All — navigation pending design verification'
                  : 'See all travelers',
              child: TextButton(
                onPressed: onSeeAll,
                style: TextButton.styleFrom(
                  disabledForegroundColor: const Color(0xFF989693),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 2,
                  ),
                  minimumSize: const Size(0, 28),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  textStyle: Theme.of(context).textTheme.labelLarge!.copyWith(
                    letterSpacing: 0,
                    fontSize: 14,
                    height: 24 / 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                child: const Text('See All'),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class BuddiesTravelerSection extends StatelessWidget {
  const BuddiesTravelerSection({
    super.key,
    required this.title,
    required this.travelers,
    this.onSeeAll,
  });
  final String title;
  final VoidCallback? onSeeAll;
  final List<BuddiesTraveler> travelers;
  @override
  Widget build(BuildContext context) {
    if (travelers.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: BuddiesSectionHeader(title: title, onSeeAll: onSeeAll),
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < travelers.length; i++) ...[
                  if (i > 0) const SizedBox(width: 16),
                  SizedBox(
                    width: (constraints.maxWidth - 40).clamp(1, 167).toDouble(),
                    child: BuddiesTravelerCard(
                      key: ValueKey(travelers[i].id),
                      traveler: travelers[i],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}
