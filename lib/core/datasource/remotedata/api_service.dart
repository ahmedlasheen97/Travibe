import 'package:dio/dio.dart';
import 'package:travibe/core/datasource/remotedata/api_exceptions.dart';
import 'package:travibe/core/datasource/remotedata/dio_client.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';

/// Opt-in observation; callers must sanitize data before logging anything.
typedef ApiRequestObserver =
    void Function(
      String method,
      String endpoint,
      Response<dynamic>? response,
      Object? failure,
      Duration elapsed,
    );

class ApiService {
  ApiService({this.observer, DioClient? client})
    : _dioClient = client ?? DioClient();
  final DioClient _dioClient;
  final ApiRequestObserver? observer;

  void _observe(
    String method,
    String endpoint,
    Response<dynamic>? response,
    Object? error,
    Duration elapsed,
  ) {
    try {
      observer?.call(method, endpoint, response, error, elapsed);
    } catch (_) {
      /* Diagnostic failures must not change request behavior. */
    }
  }

  Future<dynamic> _request(
    String method,
    String endpoint,
    Future<Response<dynamic>> Function() request,
  ) async {
    final timer = Stopwatch()..start();
    try {
      final response = await request();
      _observe(method, endpoint, response, null, timer.elapsed);
      return response.data;
    } on DioException catch (error) {
      _observe(method, endpoint, error.response, error, timer.elapsed);
      throw ApiExceptions.handleError(error);
    }
  }

  Options? _sessionOptions(String endpoint) =>
      (Uri.parse(endpoint).path.contains('buddies') ||
          Uri.parse(endpoint).path.startsWith('profile') ||
          endpoint == 'settings' ||
          endpoint == 'search/users' ||
          endpoint.startsWith('users/') ||
          endpoint == 'reports' ||
          endpoint == 'notifications' ||
          endpoint.startsWith('notifications/') ||
          endpoint.startsWith('media/') ||
          endpoint == 'user')
      ? Options(
          extra: {'sessionRevision': PreferencesManager().sessionRevision},
        )
      : null;

  Future<dynamic> get(
    String endpoint, {
    Map<String, dynamic>? queryParameters,
  }) => _request(
    'GET',
    endpoint,
    () => _dioClient.dio.get(
      endpoint,
      queryParameters: queryParameters,
      options: _sessionOptions(endpoint),
    ),
  );
  Future<dynamic> post(String endpoint, Map<String, dynamic> data) => _request(
    'POST',
    endpoint,
    () => _dioClient.dio.post(
      endpoint,
      data: data,
      options: _sessionOptions(endpoint),
    ),
  );
  Future<dynamic> put(String endpoint, Map<String, dynamic> data) => _request(
    'PUT',
    endpoint,
    () => _dioClient.dio.put(
      endpoint,
      data: data,
      options: Options(
        extra: {'sessionRevision': PreferencesManager().sessionRevision},
      ),
    ),
  );
  Future<dynamic> delete(String endpoint) => _request(
    'DELETE',
    endpoint,
    () => _dioClient.dio.delete(
      endpoint,
      options: Options(
        extra: {'sessionRevision': PreferencesManager().sessionRevision},
      ),
    ),
  );
  Future<dynamic> patch(String endpoint, Map<String, dynamic> data) => _request(
    'PATCH',
    endpoint,
    () => _dioClient.dio.patch(
      endpoint,
      data: data,
      options: _sessionOptions(endpoint),
    ),
  );

  /// OpenAPI auth.logout: revoke only the current bearer token; 204 has no body.
  /// A 401 means this token is already invalid, allowing an honest local exit.
  Future<bool> revokeCurrentToken() async {
    try {
      final response = await _dioClient.dio.post<dynamic>(
        'logout',
        options: Options(
          followRedirects: false,
          extra: {'sessionRevision': PreferencesManager().sessionRevision},
        ),
      );
      if (response.statusCode != 204) {
        throw ApiError(
          message: 'The server did not confirm sign out. Please retry.',
        );
      }
      return true;
    } on DioException catch (error) {
      if (error.response?.statusCode == 401) return false;
      throw ApiExceptions.handleError(error);
    }
  }

  /// Password must be a query parameter for this contract. Deliberately bypass
  /// request observers and shared raw error mapping: neither receives this URL,
  /// password, request options, raw response errors or transport exceptions.
  Future<void> deleteAccount(String password) async {
    if (password.isEmpty) {
      throw AccountDeletionFailure(
        message: 'Enter your current password.',
        statusCode: 422,
      );
    }
    RequestOptions? request;
    try {
      final response = await _dioClient.dio.delete<dynamic>(
        'account',
        queryParameters: {'password': password},
        options: Options(
          followRedirects: false,
          extra: {
            'sensitiveAccountDeletion': true,
            'sessionRevision': PreferencesManager().sessionRevision,
          },
        ),
      );
      request = response.requestOptions;
      if (response.statusCode != 200 ||
          response.data is! Map ||
          response.data['message'] != 'Account deleted successfully.') {
        throw AccountDeletionFailure.uncertain();
      }
    } on DioException catch (error) {
      request = error.requestOptions;
      final status = error.response?.statusCode;
      // Fixed messages only; validation bodies can echo the supplied password.
      if (status == 422) {
        throw AccountDeletionFailure(
          message: 'The password was not accepted. Check it and try again.',
          statusCode: 422,
        );
      }
      if (status == 401 || status == 403) {
        throw AccountDeletionFailure(
          message:
              'Your session could not be verified. Sign in to check your account status.',
          statusCode: status,
        );
      }
      throw AccountDeletionFailure.uncertain();
    } on AccountDeletionFailure {
      rethrow;
    } catch (_) {
      throw AccountDeletionFailure.uncertain();
    } finally {
      request?.queryParameters.clear();
    }
  }
}

class AccountDeletionFailure extends ApiError {
  AccountDeletionFailure({
    required super.message,
    super.statusCode,
    this.outcomeUncertain = false,
  });
  AccountDeletionFailure.uncertain()
    : this(
        message:
            'The deletion result could not be confirmed. Do not resubmit automatically. Check whether you can sign in, or contact support to verify your account status.',
        outcomeUncertain: true,
      );
  final bool outcomeUncertain;
}
