import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/datasource/remotedata/api_service.dart';
import 'package:travibe/features/home/data/home_account_repo.dart';
import 'package:travibe/features/shares/data/share_model.dart';

class SharesRepo {
  SharesRepo({ApiService? apiService}) : _api = apiService ?? ApiService();
  final ApiService _api;
  void _id(int id) {
    if (id < 1) throw ApiError(message: 'This content is unavailable.');
  }

  Future<int> currentUserId() async =>
      int.parse(HomeAccount.fromJson(await _api.get('user')).id);

  Future<SharesPage> list(int postId, {int page = 1, int perPage = 100}) async {
    _id(postId);
    if (page < 1 || perPage < 1 || perPage > 100) {
      throw ArgumentError('Invalid share pagination');
    }
    final result = SharesPage.fromJson(
      await _api.get(
        'posts/$postId/shares',
        queryParameters: {'page': page, 'per_page': perPage},
      ),
    );
    if (result.currentPage != page ||
        result.shares.any((s) => s.postId != postId)) {
      throw ApiError(message: 'Invalid shares page. Please try again.');
    }
    return result;
  }

  Future<ShareModel> create(int postId, CreateShareRequest request) async {
    _id(postId);
    final response = await _api.post('posts/$postId/shares', request.toJson());
    final share = ShareModel.fromJson(
      response is Map ? response['data'] : null,
    );
    if (share.postId != postId || share.platform != request.platform) {
      throw ApiError(
        message:
            'The server returned a different share. Please check your share status.',
      );
    }
    return share;
  }

  Future<void> delete(int postId, int shareId) async {
    _id(postId);
    _id(shareId);
    await _api.delete('posts/$postId/shares/$shareId');
  }

  Future<int> count(int postId) async {
    _id(postId);
    final response = await _api.get('posts/$postId');
    final data = response is Map ? response['data'] : null;
    if (data is! Map ||
        data['id'] != postId ||
        data['shares_count'] is! int ||
        (data['shares_count'] as int) < 0) {
      throw ApiError(
        message: 'Unable to refresh the share count. Please try again.',
      );
    }
    return data['shares_count'] as int;
  }
}
