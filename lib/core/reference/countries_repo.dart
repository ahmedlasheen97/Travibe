import 'package:dio/dio.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/datasource/remotedata/api_exceptions.dart';

class ReferenceCountry {
  const ReferenceCountry({
    required this.code,
    required this.name,
    required this.nameEn,
    required this.nameAr,
  });
  final String code, name, nameEn, nameAr;
  factory ReferenceCountry.fromJson(dynamic json) {
    if (json is! Map ||
        json['code'] is! String ||
        !RegExp(r'^[A-Z]{2}$').hasMatch(json['code']) ||
        ['name', 'name_en', 'name_ar'].any(
          (key) => json[key] is! String || (json[key] as String).trim().isEmpty,
        )) {
      throw const FormatException('Invalid country');
    }
    return ReferenceCountry(
      code: json['code'],
      name: json['name'],
      nameEn: json['name_en'],
      nameAr: json['name_ar'],
    );
  }
}

/// Public, locale-keyed reference data; never uses the authenticated Dio client.
class CountriesRepo {
  CountriesRepo({Dio? transport})
    : _http =
          transport ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 8),
            ),
          );
  static final shared = CountriesRepo();
  final Dio _http;
  final Map<String, List<ReferenceCountry>> _cache = {};
  final Map<String, Future<List<ReferenceCountry>>> _pending = {};
  Future<List<ReferenceCountry>> load(String locale) {
    final language = locale == 'ar' ? 'ar' : 'en';
    if (_cache[language] case final items?) return Future.value(items);
    if (_pending[language] case final request?) return request;
    final request = _load(language);
    _pending[language] = request;
    return request.whenComplete(() => _pending.remove(language));
  }

  Future<List<ReferenceCountry>> _load(String locale) async {
    try {
      final response = await _http.get<dynamic>(
        'https://travibeapp.com/api/v1/reference/countries',
        options: Options(
          headers: {'Accept': 'application/json', 'Accept-Language': locale},
          followRedirects: false,
        ),
      );
      final data = response.data is Map ? response.data['data'] : null;
      if (data is! List) throw const FormatException();
      final items = List<ReferenceCountry>.unmodifiable(
        data.map(ReferenceCountry.fromJson),
      );
      if (items.isNotEmpty) _cache[locale] = items;
      return items;
    } on DioException catch (error) {
      throw ApiExceptions.handleError(error);
    } on FormatException {
      throw ApiError(message: 'Unable to read countries. Please try again.');
    }
  }
}
