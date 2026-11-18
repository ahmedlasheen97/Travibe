import 'package:travibe/core/utils/json_parsers.dart';

/// `RecentSearchResource` from `GET/POST buddies/search/recent`.
class RecentDestination {
  const RecentDestination({
    required this.id,
    required this.destination,
    this.searchedAt,
  });

  final int id;
  final String destination;
  final DateTime? searchedAt;

  /// Null when the item is not a usable resource.
  static RecentDestination? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = parseInt(json['id']);
    final destination = json['destination'];
    if (id < 1 || destination is! String || destination.trim().isEmpty) {
      return null;
    }
    final searchedAt = json['searched_at'];
    return RecentDestination(
      id: id,
      destination: destination.trim(),
      searchedAt: searchedAt is String ? DateTime.tryParse(searchedAt) : null,
    );
  }

  bool sameDestination(String other) =>
      destination.trim().toLowerCase() == other.trim().toLowerCase();
}
