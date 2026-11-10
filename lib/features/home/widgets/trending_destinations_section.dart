import 'package:flutter/material.dart';
import 'package:travibe/core/theme/dark_colors.dart';

class TrendingDestination {
  final String name;
  final String postsCount;
  final String image;

  const TrendingDestination({
    required this.name,
    required this.postsCount,
    required this.image,
  });
}

class TrendingDestinationsSection extends StatelessWidget {
  final List<TrendingDestination> destinations;
  final VoidCallback? onSeeAllTap;

  const TrendingDestinationsSection({
    super.key,
    required this.destinations,
    this.onSeeAllTap,
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
                'Trending Destinations',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
            InkWell(
              onTap: onSeeAllTap,
              child: Text(
                'See All',
                style: TextStyle(color: DarkColors.primaryColor, fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 130,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: destinations.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) => _destinationCard(destinations[index]),
          ),
        ),
      ],
    );
  }

  Widget _destinationCard(TrendingDestination destination) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 140,
        decoration: const BoxDecoration(color: Color(0xFF141414)),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(destination.image, fit: BoxFit.cover),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black.withValues(alpha: 0.75)],
                ),
              ),
            ),
            Positioned(
              left: 10,
              right: 10,
              bottom: 10,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    destination.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    destination.postsCount,
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}