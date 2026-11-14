import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// 1×1 transparent PNG.
final transparentPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA'
  '60e6kgAAAABJRU5ErkJggg==',
);

/// Runs [body] with every HTTP GET answering a tiny PNG, so widgets that use
/// `NetworkImage` render in tests. [urls] records the requested URLs.
Future<T> withFakeNetworkImages<T>(
  Future<T> Function() body, {
  List<Uri>? urls,
}) => HttpOverrides.runZoned(body, createHttpClient: (_) => _ImageClient(urls));

class _ImageClient implements HttpClient {
  _ImageClient(this.urls);
  final List<Uri>? urls;

  @override
  bool autoUncompress = true;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    urls?.add(url);
    return _ImageRequest();
  }

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ImageRequest implements HttpClientRequest {
  @override
  final HttpHeaders headers = _Headers();

  @override
  Future<HttpClientResponse> close() async => _ImageResponse();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Headers implements HttpHeaders {
  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {}

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ImageResponse extends Stream<List<int>> implements HttpClientResponse {
  @override
  int get statusCode => HttpStatus.ok;

  @override
  int get contentLength => transparentPng.length;

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream<List<int>>.value(transparentPng).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
