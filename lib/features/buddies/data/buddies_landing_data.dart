/// Local presentation only; never a backend response or persistent user state.
enum BuddiesLandingVariant { visibilityInvitation, nearbyTravelers }

class BuddiesTraveler {
  const BuddiesTraveler({
    required this.id,
    required this.name,
    this.photoAsset,
    this.photoUrl,
    this.destination,
    this.dateLabel,
    this.interests = const [],
  });
  final String id;
  final String name;
  final String? photoAsset;
  final String? photoUrl;
  final String? destination;
  final String? dateLabel;
  final List<String> interests;
}
