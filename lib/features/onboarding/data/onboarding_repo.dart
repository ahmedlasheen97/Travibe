import 'package:dio/dio.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/datasource/remotedata/api_exceptions.dart';
import 'package:travibe/features/onboarding/data/models/app_locale.dart';
import 'package:travibe/features/onboarding/data/models/onboarding_model.dart';

class _PublicEntry {
  const _PublicEntry(this.value, this.expires, this.etag);
  final Object value;
  final DateTime expires;
  final String? etag;
}

/// Public reference content, never authenticated or stored as account state.
/// Like CountriesRepo, owns only a transport/cache, not another preferences store.
class OnboardingRepo {
  OnboardingRepo({Dio? transport, DateTime Function()? now})
    : _http =
          transport ??
          Dio(
            BaseOptions(
              baseUrl: 'https://travibeapp.com/api/v1/',
              connectTimeout: connectionTimeout,
              receiveTimeout: responseTimeout,
            ),
          ),
      _now = now ?? DateTime.now;
  // Public content can take more than eight seconds on a cold simulator
  // connection. Keep connection establishment short and response wait bounded.
  static const connectionTimeout = Duration(seconds: 8);
  static const responseTimeout = Duration(seconds: 20);
  static final shared = OnboardingRepo();
  final Dio _http;
  final DateTime Function() _now;
  final _cache = <String, _PublicEntry>{};
  final _pending = <String, Future<Object>>{};

  Future<List<OnboardingModel>> slides(String locale) =>
      _load('onboarding', locale, OnboardingModel.parse);
  Future<LocaleCatalog> locales(String locale) =>
      _load('locales', locale, LocaleCatalog.parse);

  Future<void> prefetch(String locale) async {
    Future<void> attempt(Future<Object> request) async {
      try {
        await request;
      } catch (_) {
        /* The view offers explicit retry. */
      }
    }

    await Future.wait([attempt(slides(locale)), attempt(locales(locale))]);
  }

  Future<T> _load<T extends Object>(
    String path,
    String locale,
    T Function(dynamic) parse,
  ) {
    final key = '$path:$locale';
    final entry = _cache[key];
    if (entry != null && _now().isBefore(entry.expires)) {
      return Future.value(entry.value as T);
    }
    final pending = _pending[key];
    if (pending != null) return pending.then((value) => value as T);
    final request = _request(path, locale, key, entry, parse);
    _pending[key] = request;
    return request.whenComplete(() => _pending.remove(key));
  }

  Future<T> _request<T extends Object>(
    String path,
    String locale,
    String key,
    _PublicEntry? cached,
    T Function(dynamic) parse,
  ) async {
    try {
      final response = await _http.get<dynamic>(
        path,
        options: Options(
          headers: {
            'Accept': 'application/json',
            'Accept-Language': locale,
            if (cached?.etag != null) 'If-None-Match': cached!.etag,
          },
          followRedirects: false,
          validateStatus: (status) => status == 200 || status == 304,
        ),
      );
      final T value;
      if (response.statusCode == 304) {
        if (cached == null) throw const FormatException('No cached content');
        value = cached.value as T;
      } else {
        value = parse(response.data);
      }
      final control = response.headers.value('cache-control') ?? '';
      final maxAge =
          int.tryParse(
            RegExp(r'max-age=(\d+)').firstMatch(control)?.group(1) ?? '',
          ) ??
          0;
      final age = int.tryParse(response.headers.value('age') ?? '') ?? 0;
      if (control.contains('no-store')) {
        _cache.remove(key);
      } else {
        _cache[key] = _PublicEntry(
          value,
          _now().add(
            Duration(
              seconds: control.contains('no-cache')
                  ? 0
                  : (maxAge - age).clamp(0, maxAge),
            ),
          ),
          response.headers.value('etag') ??
              (response.statusCode == 304 ? cached?.etag : null),
        );
      }
      return value;
    } on DioException catch (error) {
      throw ApiExceptions.handleError(error);
    } on FormatException {
      throw ApiError(message: 'Unable to load $path. Please try again.');
    }
  }
}
