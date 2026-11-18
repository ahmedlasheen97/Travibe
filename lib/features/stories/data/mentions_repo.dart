import 'package:dio/dio.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/datasource/remotedata/api_exceptions.dart';
import 'package:travibe/core/datasource/remotedata/dio_client.dart';
import 'package:travibe/core/models/public_user_model.dart';

/// `GET /mentions/suggestions`: without [q] the people the caller follows;
/// with it a prefix match on username or name (a leading `@` is ignored).
/// The caller, users without a username and blocked pairs are omitted.
class MentionsRepo {
  MentionsRepo({DioClient? client}) : _dio = (client ?? DioClient()).dio;
  final Dio _dio;

  static const maxQueryLength = 30;

  Future<List<PublicUserModel>> suggestions({
    String? q,
    int perPage = 20,
  }) async {
    var term = (q ?? '').trim().replaceFirst(RegExp('^@'), '');
    if (term.length > maxQueryLength) {
      term = term.substring(0, maxQueryLength);
    }
    try {
      final response = await _dio.get(
        'mentions/suggestions',
        queryParameters: {
          'per_page': perPage.clamp(1, 100),
          if (term.isNotEmpty) 'q': term,
        },
        // Dropped by DioClient if the account changes mid-request.
        options: Options(
          extra: {'sessionRevision': PreferencesManager().sessionRevision},
        ),
      );
      final body = response.data;
      if (body is! Map || body['data'] is! List) {
        throw const FormatException();
      }
      return [
            for (final item in body['data'] as List)
              if (item is Map<String, dynamic>) PublicUserModel.fromJson(item),
          ]
          .where(
            (user) =>
                user.id.isNotEmpty &&
                (user.username ?? '').isNotEmpty &&
                !user.isBlocked,
          )
          .toList(growable: false);
    } on DioException catch (e) {
      throw ApiExceptions.handleError(e);
    } on FormatException {
      throw ApiError(message: 'Unable to load people. Please try again.');
    }
  }
}
