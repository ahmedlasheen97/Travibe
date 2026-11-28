import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/datasource/remotedata/api_exceptions.dart';
import 'package:travibe/features/legal/data/legal_html_parser.dart';
import 'package:travibe/features/legal/data/legal_page.dart';

/// Loads the public website legal pages and keeps the last good copy for
/// offline use. Public, device-wide content: never uses the authenticated
/// Dio client or the session revision.
///
/// No legal-pages API exists yet (docs/BACKEND_REQUESTS.md); when it ships,
/// only [fetch] changes.
class LegalPagesRepo {
  LegalPagesRepo({
    Dio? transport,
    Future<SharedPreferences> Function()? preferences,
  }) : _http =
           transport ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 10),
               receiveTimeout: const Duration(seconds: 10),
             ),
           ),
       _preferences = preferences ?? SharedPreferences.getInstance;

  static final shared = LegalPagesRepo();
  static String cacheKey(LegalPageSlug slug) => 'legal_page_v1_${slug.name}';

  final Dio _http;
  final Future<SharedPreferences> Function() _preferences;

  /// The last page fetched successfully, or null (none or unreadable).
  Future<LegalPage?> cached(LegalPageSlug slug) async {
    try {
      final raw = (await _preferences()).getString(cacheKey(slug));
      if (raw == null) return null;
      final page = LegalPage.fromJson(jsonDecode(raw));
      return page.slug == slug ? page : null;
    } catch (_) {
      return null;
    }
  }

  Future<LegalPage> fetch(LegalPageSlug slug) async {
    final LegalPage page;
    try {
      final response = await _http.getUri<String>(
        slug.webUri,
        options: Options(
          responseType: ResponseType.plain,
          headers: {'Accept': 'text/html'},
        ),
      );
      page = LegalHtmlParser.parse(response.data ?? '', slug);
    } on DioException catch (error) {
      throw ApiExceptions.handleError(error);
    } on FormatException {
      throw ApiError(message: "Couldn't read this page. Please try again.");
    }
    try {
      await (await _preferences()).setString(
        cacheKey(slug),
        jsonEncode(page.toJson()),
      );
    } catch (_) {
      // A failed cache write must not hide a page that loaded.
    }
    return page;
  }
}
