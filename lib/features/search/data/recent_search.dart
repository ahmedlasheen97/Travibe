import 'package:flutter/foundation.dart';

/// One Home search history entry: a submitted query, or "@username" for a
/// person result (with [userId] so the row can open the profile directly).
@immutable
class RecentSearch {
  const RecentSearch(this.text, {this.userId});

  final String text;
  final String? userId;

  bool get isPerson => userId != null;
  bool sameText(RecentSearch other) =>
      text.toLowerCase() == other.text.toLowerCase();

  Map<String, dynamic> toJson() => {
    'text': text,
    if (userId != null) 'user_id': userId,
  };

  /// Accepts the current map format and legacy plain strings.
  static RecentSearch? fromJson(Object? json) {
    if (json is String) return json.trim().isEmpty ? null : RecentSearch(json);
    if (json is! Map) return null;
    final text = json['text'];
    if (text is! String || text.trim().isEmpty) return null;
    final userId = json['user_id']?.toString();
    return RecentSearch(
      text,
      userId: userId == null || userId.isEmpty ? null : userId,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is RecentSearch && other.text == text && other.userId == userId;

  @override
  int get hashCode => Object.hash(text, userId);

  @override
  String toString() => userId == null ? text : '$text#$userId';
}
