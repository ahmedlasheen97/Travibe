import 'package:travibe/core/models/cursor_pagination.dart';

// Mock-server tokens only; production never translates cursor values to ordinals.
const fixtureCursors = <int, String?>{
  1: null,
  2: 'next/+opaque==',
  3: 'older|opaque==',
  4: 'final opaque token',
};
String? fixtureCursor(int ordinal) => fixtureCursors[ordinal];
int fixturePage(String? cursor) =>
    fixtureCursors.entries.firstWhere((e) => e.value == cursor).key;
CursorPaginationMeta fixtureMeta({int current = 1, int last = 1}) =>
    CursorPaginationMeta(
      path: 'https://travibeapp.com/api/v1/posts',
      perPage: 15,
      nextCursor: current < last ? fixtureCursor(current + 1) : null,
      prevCursor: current > 1 ? fixtureCursor(current - 1) : null,
    );
Map<String, dynamic> cursorEnvelope({
  List<dynamic> data = const [],
  String? next,
  String? prev,
}) => {
  'data': data,
  'meta': {
    'path': 'https://travibeapp.com/api/v1/posts',
    'per_page': 15,
    'next_cursor': next,
    'prev_cursor': prev,
  },
};
