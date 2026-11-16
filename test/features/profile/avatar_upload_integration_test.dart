import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/media/media_upload_service.dart';
import 'package:travibe/features/profile/cubit/edit_profile_cubit.dart';
import 'package:travibe/features/profile/cubit/profile_cubit.dart';
import 'package:travibe/features/profile/cubit/profile_picture_upload_cubit.dart';
import 'package:travibe/features/profile/data/profile_avatar_repo.dart';
import 'package:travibe/features/profile/data/profile_repo.dart';
import 'package:travibe/features/profile/data/profile_update.dart';

import '../../core/media/media_upload_test.dart' show MediaApi, StorageAdapter;
import 'fixtures.dart';

class PipelineApi extends MediaApi {
  Map<String, dynamic>? patchBody;
  Object? patchError;
  @override
  Future<dynamic> patch(String endpoint, Map<String, dynamic> data) async {
    calls.add('PATCH $endpoint');
    expect(endpoint, 'profile');
    if (patchError != null) throw patchError!;
    patchBody = data;
    return {'data': []};
  }

  @override
  Future<dynamic> get(
    String endpoint, {
    Map<String, dynamic>? queryParameters,
  }) {
    if (endpoint == 'profile') {
      calls.add('GET profile');
      return Future.value({
        'data': {
          ...profileJson(),
          'avatar_url': patchBody == null
              ? null
              : 'https://example.invalid/new-avatar.png',
          'bio': patchBody?['bio'] ?? 'Exploring Egypt',
        },
      });
    }
    return super.get(endpoint, queryParameters: queryParameters);
  }
}

class Photos extends ProfileAvatarRepo {
  @override
  Future<ProfileAvatarDraft?> pick() async => ProfileAvatarDraft(
    name: 'selected.png',
    bytes: base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAQAAAACCAYAAAB/qH1jAAAAEklEQVR4nGP43+DwHxkzoAsAAHYhFfF34aTLAAAAAElFTkSuQmCC',
    ),
  );
}

typedef _Rig = ({
  ProfileCubit owner,
  EditProfileCubit editor,
  ProfilePictureUploadCubit pictures,
  ProfileAvatarDraft source,
});

void main() {
  final source = Photos();

  Future<_Rig> rig(PipelineApi api, StorageAdapter storage) async {
    final service = MediaUploadService(
      api: api,
      storageAdapter: storage,
      now: () => DateTime.utc(2026),
      wait: (_) async {},
    );
    final owner = ProfileCubit(profileRepo: ProfileRepo(apiService: api));
    await owner.loadProfile();
    final pictures = ProfilePictureUploadCubit(uploads: () => service);
    final editor = EditProfileCubit(
      owner,
      avatarRepo: source,
      pictures: pictures,
    );
    addTearDown(() async {
      await editor.close();
      await pictures.close();
      await owner.close();
      service.close();
    });
    return (
      owner: owner,
      editor: editor,
      pictures: pictures,
      source: (await source.pick())!,
    );
  }

  /// Picks a photo and waits for its background upload + attach.
  Future<void> pickAndSettle(_Rig r) async {
    await r.editor.pickAvatar();
    await r.pictures.settled();
  }

  test(
    'full real pipeline uploads on pick, attaches the avatar, then saves fields',
    () async {
      final api = PipelineApi();
      final storage = StorageAdapter()
        ..onRequest = () => api.calls.add('PUT storage');
      final r = await rig(api, storage);
      await pickAndSettle(r);
      expect(api.presignBody, {
        'filename': r.source.name,
        'content_type': 'image/png',
        'size': r.source.bytes.length,
      });
      expect(storage.bytes, r.source.bytes);
      expect(api.patchBody, {'avatar_media_id': 19});
      expect(api.calls, [
        'GET profile',
        'POST media/presign',
        'PUT storage',
        'POST media/19/finalize',
        'GET media/19',
        'GET media/19',
        'GET media/19',
        'PATCH profile',
        'GET profile',
      ]);
      expect(r.pictures.state, isA<ProfilePictureDone>());
      expect(
        (r.owner.state as ProfileLoaded).profile.avatarUrl,
        'https://example.invalid/new-avatar.png',
      );
      final draft = ProfileDraft((r.owner.state as ProfileLoaded).profile)
        ..set('bio', 'New bio');
      expect(await r.editor.save(draft), true);
      expect(api.patchBody, {'bio': 'New bio'});
      expect((r.owner.state as ProfileLoaded).profile.bio, 'New bio');
      expect(r.editor.state.saved, true);
      expect(draft.isDirty, false);
    },
  );

  test(
    'ambiguous storage timeout keeps preview and fields; Retry reconciles without writes',
    () async {
      final api = PipelineApi()..statuses = ['pending'];
      final storage = StorageAdapter()..receiveTimeout = true;
      final r = await rig(api, storage);
      final original = (r.owner.state as ProfileLoaded).profile;
      await pickAndSettle(r);
      expect(r.pictures.state, isA<ProfilePictureFailed>());
      expect(r.pictures.state.preview, r.source.bytes);
      final draft = ProfileDraft(original)..set('bio', 'Keep this draft');
      // Save never goes ahead over a failed picture.
      expect(await r.editor.save(draft), false);
      expect((r.owner.state as ProfileLoaded).profile, same(original));
      expect(draft.changes, {'bio': 'Keep this draft'});
      expect(api.patchBody, isNull);
      await r.pictures.retry();
      expect(r.pictures.state, isA<ProfilePictureFailed>());
      expect(storage.requests, 1);
      expect(api.calls.where((e) => e.startsWith('POST')), [
        'POST media/presign',
      ]);
      // Only an authoritative server ready result permits claiming this ID.
      api.statuses = ['ready'];
      await r.pictures.retry();
      expect(r.pictures.state, isA<ProfilePictureDone>());
      expect(api.patchBody, {'avatar_media_id': 19});
      expect(storage.requests, 1);
      expect(api.calls.where((e) => e.contains('finalize')), isEmpty);
      expect(await r.editor.save(draft), true);
      expect(api.patchBody, {'bio': 'Keep this draft'});
    },
  );

  test(
    'observed top-level media ready response recovers failed finalize parsing and PATCHes without another upload',
    () async {
      final api = PipelineApi()
        ..finalizeResponse = {'unexpected': {}}
        ..statusEnvelope = 'media'
        ..statuses = ['ready'];
      final storage = StorageAdapter();
      final r = await rig(api, storage);
      await pickAndSettle(r);
      expect(r.pictures.state, isA<ProfilePictureFailed>());
      expect(api.patchBody, isNull);
      await r.pictures.retry();
      expect(r.pictures.state, isA<ProfilePictureDone>());
      expect(api.patchBody, {'avatar_media_id': 19});
      expect(storage.requests, 1);
      expect(api.calls.where((c) => c == 'POST media/presign'), hasLength(1));
      expect(api.calls.where((c) => c.contains('finalize')), hasLength(1));
      expect(api.calls.last, 'GET profile');
      expect(
        (r.owner.state as ProfileLoaded).profile.avatarUrl,
        'https://example.invalid/new-avatar.png',
      );
    },
  );

  test(
    'finalize 409 reconciles ready media then performs avatar-only PATCH and refresh',
    () async {
      final api = PipelineApi()
        ..finalizeError = ApiError(
          message: 'Already finalized',
          statusCode: 409,
        )
        ..statuses = ['processing', 'ready'];
      final storage = StorageAdapter();
      final r = await rig(api, storage);
      await pickAndSettle(r);
      expect(r.pictures.state, isA<ProfilePictureDone>());
      expect(api.patchBody, {'avatar_media_id': 19});
      expect(api.calls.where((c) => c.contains('finalize')), [
        'POST media/19/finalize',
      ]);
      expect(storage.requests, 1);
      expect(api.calls.last, 'GET profile');
      expect(
        (r.owner.state as ProfileLoaded).profile.avatarUrl,
        'https://example.invalid/new-avatar.png',
      );
    },
  );

  test(
    'finalize 422 fails the picture and keeps the existing profile and fields',
    () async {
      final validation = ApiError(
        message: 'Invalid uploaded image',
        statusCode: 422,
        fieldErrors: {
          'media': ['Invalid uploaded image'],
        },
      );
      final api = PipelineApi()..finalizeError = validation;
      final storage = StorageAdapter();
      final r = await rig(api, storage);
      final original = (r.owner.state as ProfileLoaded).profile;
      await pickAndSettle(r);
      expect(r.pictures.state, isA<ProfilePictureFailed>());
      expect(r.pictures.state.preview, r.source.bytes);
      final draft = ProfileDraft(original)..set('bio', 'Keep my changes');
      expect(await r.editor.save(draft), false);
      expect(draft.changes, {'bio': 'Keep my changes'});
      expect((r.owner.state as ProfileLoaded).profile, same(original));
      expect(api.patchBody, isNull);
      expect(api.calls.where((c) => c.startsWith('GET media')), isEmpty);
      expect(storage.requests, 1);
    },
  );

  test(
    'failed processing never PATCHes or replaces server avatar; PATCH error reuses ready media on retry',
    () async {
      final api = PipelineApi()..statuses = ['failed'];
      final storage = StorageAdapter();
      final r = await rig(api, storage);
      final original = (r.owner.state as ProfileLoaded).profile;
      await pickAndSettle(r);
      expect(r.pictures.state, isA<ProfilePictureFailed>());
      expect(api.patchBody, isNull);
      expect((r.owner.state as ProfileLoaded).profile, same(original));
      api.statuses = ['ready'];
      api.patchError = ApiError(message: 'Invalid', statusCode: 422);
      await r.pictures.retry();
      expect(r.pictures.state, isA<ProfilePictureFailed>());
      expect(storage.requests, 2);
      api.patchError = null;
      await r.pictures.retry();
      expect(r.pictures.state, isA<ProfilePictureDone>());
      expect(storage.requests, 2);
      expect(api.patchBody, {'avatar_media_id': 19});
    },
  );
}
