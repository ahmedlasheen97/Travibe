import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:travibe/core/datasource/remotedata/buddies_diagnostics.dart';

void main() {
  test(
    '422 logs allowlisted fields and request ID without headers or credentials',
    () {
      final original = debugPrint;
      final messages = <String>[];
      debugPrint = (String? message, {int? wrapWidth}) {
        messages.add(message ?? '');
      };
      addTearDown(() => debugPrint = original);
      final request = RequestOptions(
        path: 'https://travibeapp.com/api/v1/profile/location',
        method: 'PUT',
        headers: {'Authorization': 'secret-token'},
        data: {'location': 'Cairo, EG', 'password': 'private-password'},
      );
      logBuddiesResponse(
        Response(
          requestOptions: request,
          statusCode: 422,
          data: {'message': 'Invalid'},
          headers: Headers.fromMap({
            'x-request-id': ['test-request-123'],
          }),
        ),
      );
      expect(messages.single, contains('PUT /api/v1/profile/location'));
      expect(messages.single, contains('Cairo, EG'));
      expect(messages.single, contains('test-request-123'));
      expect(messages.single, isNot(contains('secret-token')));
      expect(messages.single, isNot(contains('private-password')));
    },
  );
  test(
    'empty search logs city country and filters independently of pagination URL',
    () {
      final original = debugPrint;
      final messages = <String>[];
      debugPrint = (String? message, {int? wrapWidth}) {
        messages.add(message ?? '');
      };
      addTearDown(() => debugPrint = original);
      final request = RequestOptions(
        path:
            'https://travibeapp.com/api/v1/buddies/search?city=Cairo&country_code=EG&page=2&gender%5B%5D=female',
      );
      logBuddiesResponse(
        Response(requestOptions: request, statusCode: 200, data: {'data': []}),
      );
      expect(messages.single, contains('Cairo'));
      expect(messages.single, contains('EG'));
      expect(messages.single, contains('female'));
    },
  );
}
