import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/screen_util.dart';
import 'package:travibe/core/datasource/remotedata/api_service.dart';
import 'package:travibe/core/datasource/remotedata/dio_client.dart';
import 'package:travibe/core/media/media_upload_service.dart';
import 'package:travibe/core/media/upload_diagnostics.dart';
import 'package:travibe/features/profile/cubit/profile_cubit.dart';
import 'package:travibe/features/profile/data/profile_avatar_repo.dart';
import 'package:travibe/features/profile/data/profile_repo.dart';
import 'package:travibe/features/profile/screens/edit_profile_screen.dart';

import '../../core/media/media_upload_test.dart' show StorageAdapter;
import 'fixtures.dart';

class _Client extends DioClient {
  _Client(this.client);
  final Dio client;
  @override
  Dio get dio => client;
}

class _PhotoRepo extends ProfileAvatarRepo {
  final photo = ProfileAvatarDraft(
    name: 'avatar.png',
    bytes: base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAQAAAACCAYAAAB/qH1jAAAAEklEQVR4nGP43+DwHxkzoAsAAHYhFfF34aTLAAAAAElFTkSuQmCC',
    ),
  );
  @override
  Future<ProfileAvatarDraft?> pick() async => photo;
}

/// Synthetic values reproduce the runtime sequence and HTTP statuses supplied
/// by the user. This is a real Dio adapter boundary test, not a live upload.
class _PipelineAdapter implements HttpClientAdapter {
  _PipelineAdapter(this.events);
  final List<String> events;
  Map<String, dynamic>? presign;
  Map<String, dynamic>? patch;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final bytes = requestStream == null
        ? <int>[]
        : await requestStream.fold<List<int>>([], (a, b) => a..addAll(b));
    final path = options.uri.path.replaceFirst('/api/v1/', '');
    final method = options.method;
    dynamic response;
    var status = 200;
    if (path == 'profile' && method == 'GET') {
      response = {
        'data': {
          ...profileJson(),
          'avatar_url': patch == null
              ? null
              : 'https://example.invalid/updated-avatar.png',
          'name': patch?['full_name'] ?? 'Mona Hassan',
        },
      };
    } else if (path == 'media/presign' && method == 'POST') {
      status = 201;
      presign = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      response = {
        'media': {'id': 41, 'type': 'image', 'status': 'pending'},
        'upload_url':
            'https://storage.example.invalid/photo.png?signature=test-only%2Fsignature',
        'upload_method': 'PUT',
        'upload_headers': {
          'Host': ['storage.example.invalid'],
        },
        'expires_at': '2030-10-21T00:00:00Z',
      };
    } else if (path == 'media/41/finalize' && method == 'POST') {
      response = {
        'media': {'id': 41, 'type': 'image', 'status': 'processing'},
      };
    } else if (path == 'media/41' && method == 'GET') {
      response = {
        'media': {'id': 41, 'type': 'image', 'status': 'ready'},
      };
    } else if (path == 'profile' && method == 'PATCH') {
      patch = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      response = {'data': []};
    } else {
      throw StateError('Unexpected test request');
    }
    events.add('$method $path $status');
    return ResponseBody.fromString(
      jsonEncode(response),
      status,
      headers: {
        'content-type': ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  testWidgets(
    'one Save tap completes presign 201 PUT 200 finalize processing 200 ready 200 PATCH 200 refresh 200',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final events = <String>[];
      final apiAdapter = _PipelineAdapter(events);
      final dio = Dio(BaseOptions(baseUrl: 'https://example.invalid/api/v1/'))
        ..httpClientAdapter = apiAdapter;
      final api = ApiService(
        client: _Client(dio),
        observer: (method, endpoint, response, error, elapsed) {
          observeMediaApiRequest(method, endpoint, response, error, elapsed);
          observeProfileApiRequest(method, endpoint, response, error, elapsed);
        },
      );
      final storage = StorageAdapter()
        ..onRequest = () => events.add('PUT storage 200');
      final service = MediaUploadService(
        api: api,
        storageAdapter: storage,
        now: () => DateTime.utc(2026),
        wait: (_) async {},
      );
      final owner = ProfileCubit(profileRepo: ProfileRepo(apiService: api));
      await tester.runAsync(owner.loadProfile);
      final initial = (owner.state as ProfileLoaded).profile;
      final photos = _PhotoRepo();
      addTearDown(() async {
        await owner.close();
        service.close();
        dio.close(force: true);
      });
      await tester.pumpWidget(
        withScreenUtil(
          MaterialApp(
            theme: ThemeData.dark(),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => EditProfileScreen(
                        profile: initial,
                        owner: owner,
                        avatarRepo: photos,
                        mediaUpload: service,
                      ),
                    ),
                  ),
                  child: const Text('Open editor'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open editor'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('full_name')),
        'Updated name',
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('pick-profile-avatar')),
      );
      await tester.tap(find.byKey(const ValueKey('pick-profile-avatar')));
      await tester.pumpAndSettle();
      expect(events, ['GET profile 200']);
      final save = find.widgetWithText(ElevatedButton, 'Save Changes');
      await tester.runAsync(() async {
        final refreshed = owner.stream.firstWhere(
          (state) =>
              state is ProfileLoaded &&
              state.profile.avatarUrl ==
                  'https://example.invalid/updated-avatar.png',
        );
        await tester.tap(save); // Exactly one Save tap for the entire pipeline.
        await refreshed.timeout(const Duration(seconds: 5));
      });
      await tester.pumpAndSettle();
      expect(events, [
        'GET profile 200',
        'POST media/presign 201',
        'PUT storage 200',
        'POST media/41/finalize 200',
        'GET media/41 200',
        'PATCH profile 200',
        'GET profile 200',
      ]);
      expect(storage.requests, 1);
      expect(storage.bytes, photos.photo.bytes);
      expect(
        storage.request!.headers.keys.map((k) => k.toLowerCase()),
        isNot(contains('authorization')),
      );
      expect(apiAdapter.presign, {
        'filename': 'avatar.png',
        'content_type': 'image/png',
        'size': photos.photo.bytes.length,
      });
      expect(apiAdapter.patch, {
        'full_name': 'Updated name',
        'avatar_media_id': 41,
      });
      expect(find.byType(EditProfileScreen), findsNothing);
      expect(find.text('Open editor'), findsOneWidget);
      expect(find.textContaining('uncertain'), findsNothing);
      expect(
        (owner.state as ProfileLoaded).profile.avatarUrl,
        'https://example.invalid/updated-avatar.png',
      );
      expect(tester.takeException(), isNull);
    },
  );
}
