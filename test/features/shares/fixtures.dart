import 'dart:async';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/features/shares/data/share_model.dart';
import 'package:travibe/features/shares/data/shares_repo.dart';

Map<String, dynamic> shareJson({
  int id = 73,
  int userId = 7,
  int postId = 10,
  String platform = 'internal',
  String? comment,
}) => {
  'id': id,
  'user_id': userId,
  'post_id': postId,
  'platform': platform,
  'comment': comment,
  'created_at': null,
  'updated_at': null,
  'user': {'id': userId, 'name': 'Traveller', 'avatar_url': null},
};
ShareModel share({
  int id = 73,
  int userId = 7,
  int postId = 10,
  String platform = 'internal',
  String? comment,
}) => ShareModel.fromJson(
  shareJson(
    id: id,
    userId: userId,
    postId: postId,
    platform: platform,
    comment: comment,
  ),
);

class ShareRead {
  ShareRead(this.postId, this.page);
  final int postId;
  final int page;
  final result = Completer<SharesPage>();
}

class MemorySharesRepo extends SharesRepo {
  final Map<int, List<ShareModel>> records = {};
  final Map<int, int> counts = {10: 2};
  final List<ShareRead> reads = [];
  final List<({int postId, CreateShareRequest request})> creates = [];
  final List<({int postId, int shareId})> deletes = [];
  final List<int> countReads = [];
  int viewerId = 7;
  int identityReads = 0;
  ApiError? identityError;
  ApiError? listError;
  ApiError? createError;
  ApiError? deleteError;
  ApiError? countError;
  bool holdReads = false;
  Completer<ShareModel>? createGate;
  Completer<void>? deleteGate;
  Completer<int>? countGate;
  @override
  Future<int> currentUserId() async {
    identityReads++;
    if (identityError != null) throw identityError!;
    return viewerId;
  }

  @override
  Future<SharesPage> list(int postId, {int page = 1, int perPage = 100}) async {
    final call = ShareRead(postId, page);
    reads.add(call);
    if (holdReads) return call.result.future;
    if (listError != null) throw listError!;
    final values = records[postId] ?? [];
    return SharesPage(
      shares: values.skip((page - 1) * 2).take(2).toList(),
      currentPage: page,
      lastPage: ((values.length + 1) ~/ 2).clamp(1, 100),
      total: values.length,
    );
  }

  @override
  Future<ShareModel> create(int postId, CreateShareRequest request) async {
    creates.add((postId: postId, request: request));
    if (createError != null) throw createError!;
    final result = createGate == null
        ? share(
            userId: viewerId,
            postId: postId,
            comment: request.comment,
            platform: request.platform.value,
          )
        : await createGate!.future;
    records[postId] = [...?records[postId], result];
    if (result.platform == SharePlatform.internal) {
      counts[postId] = (counts[postId] ?? 0) + 1;
    }
    return result;
  }

  @override
  Future<void> delete(int postId, int shareId) async {
    deletes.add((postId: postId, shareId: shareId));
    if (deleteError != null) throw deleteError!;
    if (deleteGate != null) await deleteGate!.future;
    final target = records[postId]!.firstWhere((s) => s.id == shareId);
    records[postId]!.removeWhere((s) => s.id == shareId);
    if (target.platform == SharePlatform.internal) {
      counts[postId] = ((counts[postId] ?? 0) - 1).clamp(0, 100000);
    }
  }

  @override
  Future<int> count(int postId) async {
    countReads.add(postId);
    if (countError != null) throw countError!;
    if (countGate != null) return countGate!.future;
    return counts[postId] ?? 0;
  }
}

Future<void> flushShares() => Future<void>.delayed(Duration.zero);
