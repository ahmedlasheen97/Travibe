import '../../helpers/cursor_fixtures.dart';
import 'dart:async';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/features/comments/data/comment_model.dart';
import 'package:travibe/features/comments/data/comments_repo.dart';

Map<String, dynamic> commentJson(
  int id, {
  int? parentId,
  String? content = 'Hello',
  bool canEdit = true,
  bool canDelete = true,
  int replies = 0,
}) => {
  'id': id,
  'post_id': 10,
  'parent_id': parentId,
  'content': content,
  'user': {'id': 7, 'name': 'Sara', 'avatar_url': null},
  'media': [],
  'created_at': '2026-10-13T12:00:00Z',
  'updated_at': null,
  'deleted_at': null,
  'likes_count': 0,
  'is_liked': false,
  'replies_count': replies,
  'permissions': {'can_edit': canEdit, 'can_delete': canDelete},
};
CommentModel comment(
  int id, {
  int? parentId,
  String? content = 'Hello',
  bool canEdit = true,
  bool canDelete = true,
  int replies = 0,
}) => CommentModel.fromJson(
  commentJson(
    id,
    parentId: parentId,
    content: content,
    canEdit: canEdit,
    canDelete: canDelete,
    replies: replies,
  ),
);
CommentsPage page(
  List<CommentModel> comments, {
  int current = 1,
  int last = 1,
}) => CommentsPage(
  comments: comments,
  pagination: fixtureMeta(current: current, last: last),
);

class ReadCall {
  ReadCall(this.parentId, this.page);
  final int? parentId;
  final int page;
  final result = Completer<CommentsPage>();
}

class MemoryCommentsRepo extends CommentsRepo {
  final Map<int, CommentModel> items = {};
  final Map<int, CommentModel> deleted = {};
  final List<ReadCall> reads = [];
  final List<String> writes = [];
  final List<Completer<int>> counts = [];
  int countCalls = 0;
  int nextId = 100;
  bool holdReads = false;
  bool holdCounts = false;
  bool cascade = false;
  Completer<void>? writeGate;
  ApiError? mutationError;
  ApiError? readError;
  ApiError? countError;

  @override
  Future<CommentsPage> list(
    int postId, {
    int? parentId,
    String? cursor,
    int perPage = 15,
  }) async {
    final page = fixturePage(cursor);
    final call = ReadCall(parentId, page);
    reads.add(call);
    if (holdReads) return call.result.future;
    if (readError != null) throw readError!;
    final values = items.values.where((c) => c.parentId == parentId).toList()
      ..sort((a, b) => b.id.compareTo(a.id));
    const size = 2;
    final last = ((values.length + size - 1) ~/ size).clamp(1, 999);
    return CommentsPage(
      comments: values
          .skip((page - 1) * size)
          .take(size)
          .map(
            (c) => comment(
              c.id,
              parentId: c.parentId,
              content: c.content,
              canEdit: c.permissions.canEdit,
              canDelete: c.permissions.canDelete,
              replies: items.values
                  .where((child) => child.parentId == c.id)
                  .length,
            ),
          )
          .toList(),
      pagination: fixtureMeta(current: page, last: last),
    );
  }

  Future<void> _write(String name) async {
    writes.add(name);
    if (writeGate != null) await writeGate!.future;
    if (mutationError != null) throw mutationError!;
  }

  @override
  Future<CommentModel> create(int postId, CommentTextRequest request) async {
    await _write('create');
    final value = comment(
      nextId++,
      parentId: request.parentId,
      content: request.content.trim(),
    );
    items[value.id] = value;
    return value;
  }

  @override
  Future<CommentModel> edit(
    int postId,
    int id,
    CommentTextRequest request,
  ) async {
    await _write('edit');
    final value = comment(
      id,
      parentId: items[id]?.parentId,
      content: request.content.trim(),
    );
    items[id] = value;
    return value;
  }

  @override
  Future<void> delete(int postId, int id) async {
    await _write('delete');
    final value = items.remove(id);
    if (value != null) deleted[id] = value;
    if (cascade) {
      for (final child
          in items.values.where((c) => c.parentId == id).toList()) {
        deleted[child.id] = items.remove(child.id)!;
      }
    }
  }

  @override
  Future<CommentModel> restore(int postId, int id) async {
    await _write('restore');
    final value = deleted.remove(id)!;
    items[id] = value;
    return value;
  }

  @override
  Future<CommentModel> get(int postId, int id) async {
    final value = items[id];
    if (value == null) throw ApiError(message: 'Not found', statusCode: 404);
    return comment(
      id,
      parentId: value.parentId,
      content: value.content,
      replies: items.values.where((c) => c.parentId == id).length,
    );
  }

  @override
  Future<int> commentCount(int postId) async {
    countCalls++;
    if (holdCounts) {
      final result = Completer<int>();
      counts.add(result);
      return result.future;
    }
    if (countError != null) throw countError!;
    return items.length;
  }
}
