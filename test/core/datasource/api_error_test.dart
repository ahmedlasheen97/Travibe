import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/datasource/remotedata/api_exceptions.dart';
import 'package:travibe/core/datasource/remotedata/api_service.dart';
import 'package:travibe/features/auth/data/auth_repo.dart';

class _ThrowingApi extends ApiService {
  _ThrowingApi(this.error);
  final Object error;

  @override
  Future<dynamic> post(String endpoint, Map<String, dynamic> data) async =>
      throw error;
}

DioException _bad(int status, Object? data) {
  final options = RequestOptions(path: 'x');
  return DioException(
    requestOptions: options,
    type: DioExceptionType.badResponse,
    response: Response(requestOptions: options, statusCode: status, data: data),
  );
}

void main() {
  group('ApiError.messageOf', () {
    test('uses the server message of an ApiError', () {
      expect(
        ApiError.messageOf(ApiError(message: 'The code is invalid.')),
        'The code is invalid.',
      );
    });

    test('falls back for non-ApiErrors, empty and wrapped messages', () {
      expect(ApiError.messageOf(StateError('x')), ApiError.fallbackMessage);
      expect(ApiError.messageOf(null), ApiError.fallbackMessage);
      expect(
        ApiError.messageOf(ApiError(message: '  ')),
        ApiError.fallbackMessage,
      );
      final nested = ApiError(
        message: 'An unexpected error occurred: ${ApiError(message: 'x')}',
      );
      expect(ApiError.messageOf(nested), ApiError.fallbackMessage);
    });
  });

  group('ApiExceptions.handleError', () {
    test('keeps server and validation messages', () {
      expect(
        ApiExceptions.handleError(
          _bad(422, {
            'message': 'The given data was invalid.',
            'errors': {
              'code': ['The code is invalid.'],
            },
          }),
        ).message,
        'The code is invalid.',
      );
      expect(
        ApiExceptions.handleError(
          _bad(401, {'message': 'Unauthenticated.'}),
        ).message,
        'Unauthenticated.',
      );
    });

    test('never shows status codes or raw bodies', () {
      for (final error in [
        _bad(500, null),
        _bad(500, '<html>Server Error</html>'),
        _bad(500, <String, dynamic>{}),
      ]) {
        expect(
          ApiExceptions.handleError(error).message,
          ApiError.fallbackMessage,
        );
      }
      expect(
        ApiExceptions.handleError(
          DioException(requestOptions: RequestOptions(path: 'x')),
        ).message,
        ApiError.fallbackMessage,
      );
    });
  });

  group('AuthRepo does not wrap ApiErrors twice', () {
    final server = ApiError(message: 'The code is invalid.', statusCode: 422);

    test('verify, reset and forgot rethrow the same ApiError', () async {
      final repo = AuthRepo(apiService: _ThrowingApi(server));
      for (final call in <Future<Object?> Function()>[
        () => repo.verifyEmailCode(email: 'a@b.c', code: '1234'),
        () => repo.verifyResetCode(email: 'a@b.c', code: '1234'),
        () => repo.forgotPassword(email: 'a@b.c'),
        () => repo.resetPassword(
          token: 't',
          email: 'a@b.c',
          password: 'Password1',
          passwordConfirmation: 'Password1',
        ),
      ]) {
        await expectLater(call(), throwsA(same(server)));
      }
    });

    test('other failures become the friendly fallback', () async {
      final repo = AuthRepo(apiService: _ThrowingApi(StateError('boom')));
      await expectLater(
        repo.verifyEmailCode(email: 'a@b.c', code: '1234'),
        throwsA(
          isA<ApiError>().having(
            (e) => e.message,
            'message',
            ApiError.fallbackMessage,
          ),
        ),
      );
    });
  });
}
