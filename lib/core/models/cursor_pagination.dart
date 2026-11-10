import 'package:travibe/core/datasource/remotedata/api_error.dart';

/// Cursor values are opaque: never trim, decode, increment, or build them locally.
class CursorPaginationMeta {
  const CursorPaginationMeta({
    required this.path,
    required this.perPage,
    this.nextCursor,
    this.prevCursor,
  });
  final String path;
  final int perPage;
  final String? nextCursor, prevCursor;
  bool get hasMore => nextCursor != null;

  factory CursorPaginationMeta.fromJson(dynamic json) {
    if (json is! Map ||
        json['path'] is! String ||
        (json['path'] as String).isEmpty ||
        json['per_page'] is! int ||
        (json['per_page'] as int) < 1 ||
        (json['per_page'] as int) > 100) {
      throw ApiError(
        message: 'Unable to read cursor pagination. Please retry.',
      );
    }
    for (final key in ['next_cursor', 'prev_cursor']) {
      if (!json.containsKey(key) ||
          (json[key] != null &&
              (json[key] is! String || (json[key] as String).isEmpty))) {
        throw ApiError(
          message: 'Unable to read cursor pagination. Please retry.',
        );
      }
    }
    return CursorPaginationMeta(
      path: json['path'],
      perPage: json['per_page'],
      nextCursor: json['next_cursor'],
      prevCursor: json['prev_cursor'],
    );
  }
}

Map<String, dynamic> cursorQuery({String? cursor, int perPage = 15}) {
  if (perPage < 1 || perPage > 100 || cursor == '') {
    throw ArgumentError('Invalid cursor pagination');
  }
  return {'per_page': perPage, 'cursor': ?cursor};
}

class CursorPage<T> {
  CursorPage({required Iterable<T> items, required this.pagination})
    : items = List.unmodifiable(items);
  final List<T> items;
  final CursorPaginationMeta pagination;
  bool get hasMore => pagination.hasMore;

  factory CursorPage.fromJson(dynamic json, T Function(dynamic) parseItem) {
    if (json is! Map || json['data'] is! List) {
      throw ApiError(
        message: 'Unable to read paginated results. Please retry.',
      );
    }
    final pagination = CursorPaginationMeta.fromJson(json['meta']);
    return CursorPage(
      items: (json['data'] as List).map(parseItem),
      pagination: pagination,
    );
  }
}

/// One instance per feed/author/thread/filter scope. Failed reads never advance it.
class CursorProgress {
  String? nextCursor, prevCursor;
  final _consumed = <String>{};
  bool get hasMore => nextCursor != null;

  void clear() {
    nextCursor = prevCursor = null;
    _consumed.clear();
  }

  void accept(CursorPaginationMeta meta, {String? requestedCursor}) {
    if (requestedCursor == null) {
      clear();
    } else {
      _consumed.add(requestedCursor);
    }
    prevCursor = meta.prevCursor;
    nextCursor = _consumed.contains(meta.nextCursor) ? null : meta.nextCursor;
  }
}
