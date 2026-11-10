import 'package:flutter/material.dart';
import 'package:travibe/features/buddies/data/buddies_landing_data.dart';

class BuddiesTravelerCard extends StatelessWidget {
  const BuddiesTravelerCard({super.key, required this.traveler});
  final BuddiesTraveler traveler;
  static const _detail = TextStyle(
    letterSpacing: 0,
    color: Colors.white,
    fontSize: 12,
    height: 16 / 12,
    fontWeight: FontWeight.w500,
  );
  @override
  Widget build(BuildContext context) {
    final photo = traveler.photoAsset;
    const fallback = ColoredBox(
      color: Color(0xFF2A2A2A),
      child: Center(
        child: Icon(Icons.person_outline, size: 48, color: Colors.white54),
      ),
    );
    return Semantics(
      container: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: ColoredBox(
          color: const Color(0xFF171717),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              ExcludeSemantics(
                child: SizedBox(
                  height: 134,
                  child: traveler.photoUrl != null
                      ? Image.network(
                          traveler.photoUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => fallback,
                          loadingBuilder: (_, child, progress) =>
                              progress == null ? child : fallback,
                        )
                      : photo == null
                      ? fallback
                      : Image.asset(
                          photo,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => fallback,
                        ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      traveler.name,
                      style: const TextStyle(
                        letterSpacing: 0,
                        color: Colors.white,
                        fontSize: 14,
                        height: 24 / 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (traveler.destination case final String destination)
                      Text(destination, style: _detail),
                    if (traveler.dateLabel case final String dates) ...[
                      const SizedBox(height: 4),
                      Text(
                        dates,
                        style: _detail.copyWith(
                          color: const Color(0xFFBDBCBB),
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                    if (traveler.interests.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 4,
                        runSpacing: 8,
                        children: [
                          for (final item in traveler.interests)
                            BuddiesInterestChip(label: item),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class BuddiesInterestChip extends StatelessWidget {
  const BuddiesInterestChip({super.key, required this.label});
  final String label;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0x528361DA),
      borderRadius: BorderRadius.circular(24),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Text(
        label,
        style: const TextStyle(
          letterSpacing: 0,
          color: Colors.white,
          fontSize: 12,
          height: 16 / 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    ),
  );
}
