import 'package:travibe/core/datasource/remotedata/api_error.dart';

enum ReferenceKind {
  languages('languages', 4),
  interests('interests', 6),
  travelStyles('travel-styles', 3);

  const ReferenceKind(this.path, this.limit);
  final String path;
  final int limit;
}

class ReferenceItem {
  static const unavailableMessage =
      'Reference options are temporarily unavailable. Please try again later.';
  const ReferenceItem({
    required this.slug,
    required this.name,
    required this.nameEn,
    required this.nameAr,
    this.status,
  });
  final String slug;
  final String name;
  final String nameEn;
  final String nameAr;
  final String? status;

  String label(String languageCode) {
    final localized = languageCode == 'ar'
        ? nameAr
        : languageCode == 'en'
        ? nameEn
        : name;
    return localized.isEmpty ? name : localized;
  }

  factory ReferenceItem.fromJson(Map<String, dynamic> json) {
    for (final field in ['slug', 'name', 'name_en', 'name_ar']) {
      if (json[field] is! String || (json[field] as String).trim().isEmpty) {
        throw ApiError(message: 'Invalid reference catalog response.');
      }
    }
    if (json['status'] != null && json['status'] is! String) {
      throw ApiError(message: 'Invalid reference catalog response.');
    }
    return ReferenceItem(
      slug: json['slug'] as String,
      name: json['name'] as String,
      nameEn: json['name_en'] as String,
      nameAr: json['name_ar'] as String,
      status: json['status'] as String?,
    );
  }

  static List<ReferenceItem> parseCatalog(dynamic response) {
    if (response is Map &&
        response['data'] is Map &&
        (response['data'] as Map).containsKey('__PHP_Incomplete_Class_Name')) {
      // Verified live backend serialization failure, not a list of options.
      // No slug/label can be recovered from this object.
      throw ApiError(message: unavailableMessage);
    }
    if (response is! Map || response['data'] is! List) {
      throw ApiError(message: 'Invalid reference catalog response.');
    }
    final items = <ReferenceItem>[];
    final slugs = <String>{};
    for (final raw in response['data'] as List) {
      if (raw is! Map) {
        throw ApiError(message: 'Invalid reference catalog response.');
      }
      final item = ReferenceItem.fromJson(Map<String, dynamic>.from(raw));
      if (!slugs.add(item.slug)) {
        throw ApiError(message: 'Duplicate reference catalog value.');
      }
      items.add(item);
    }
    return List.unmodifiable(items);
  }
}

enum CatalogStatus { loading, loaded, failure }

class ReferenceCatalog {
  const ReferenceCatalog({
    this.status = CatalogStatus.loading,
    this.items = const [],
    this.error = '',
  });
  final CatalogStatus status;
  final List<ReferenceItem> items;
  final String error;
}

// Match artwork by the catalog's English name, never by deriving a slug.
ReferenceItem? referenceForName(List<ReferenceItem> items, String name) {
  for (final item in items) {
    if (item.nameEn.toLowerCase() == name.toLowerCase()) return item;
  }
  return null;
}

List<ReferenceItem> orderReferences(
  List<ReferenceItem> items,
  List<String> names,
) {
  final ordered = <ReferenceItem>[];
  for (final name in names) {
    final item = referenceForName(items, name);
    if (item != null) ordered.add(item);
  }
  return [...ordered, ...items.where((item) => !ordered.contains(item))];
}
