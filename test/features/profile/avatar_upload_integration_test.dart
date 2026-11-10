import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/media/media_upload_service.dart';
import 'package:travibe/features/profile/cubit/edit_profile_cubit.dart';
import 'package:travibe/features/profile/cubit/profile_cubit.dart';
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

void main() {
  test(
    'full real pipeline preserves source metadata then refreshes canonical avatar',
    () async {
      final api = PipelineApi();
      final storage = StorageAdapter()
        ..onRequest = () => api.calls.add('PUT storage');
      final service = MediaUploadService(
        api: api,
        storageAdapter: storage,
        now: () => DateTime.utc(2026),
        wait: (_) async {},
      );
      final owner = ProfileCubit(profileRepo: ProfileRepo(apiService: api));
      await owner.loadProfile();
      final editor = EditProfileCubit(
        owner,
        avatarRepo: Photos(),
        mediaUpload: service,
      );
      addTearDown(() async {
        await editor.close();
        await owner.close();
        service.close();
      });
      await editor.pickAvatar();
      final source = editor.state.avatar!;
      expect(api.calls, ['GET profile']); // Selection never uploads.
      final draft = ProfileDraft((owner.state as ProfileLoaded).profile)
        ..set('bio', 'New bio');
      expect(await editor.save(draft), true);
      expect(api.presignBody, {
        'filename': source.name,
        'content_type': 'image/png',
        'size': source.bytes.length,
      });
      expect(storage.bytes, source.bytes);
      expect(api.patchBody, {'bio': 'New bio', 'avatar_media_id': 19});
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
      expect(
        (owner.state as ProfileLoaded).profile.avatarUrl,
        'https://example.invalid/new-avatar.png',
      );
      expect((owner.state as ProfileLoaded).profile.bio, 'New bio');
      expect(editor.state.saved, true);
      expect(draft.isDirty, false);
    },
  );

  test(
    'ambiguous storage timeout preserves preview and fields; Save retries reconcile without writes',
    () async {
      final api = PipelineApi()..statuses = ['pending'];
      final storage = StorageAdapter()..receiveTimeout = true;
      final service = MediaUploadService(
        api: api,
        storageAdapter: storage,
        now: () => DateTime.utc(2026),
        wait: (_) async {},
      );
      final owner = ProfileCubit(profileRepo: ProfileRepo(apiService: api));
      await owner.loadProfile();
      final original = (owner.state as ProfileLoaded).profile;
      final editor = EditProfileCubit(
        owner,
        avatarRepo: Photos(),
        mediaUpload: service,
      );
      addTearDown(() async {
        await editor.close();
        await owner.close();
        service.close();
      });
      await editor.pickAvatar();
      final photo = editor.state.avatar;
      final draft = ProfileDraft(original)..set('bio', 'Keep this draft');
      expect(await editor.save(draft), false);
      expect((owner.state as ProfileLoaded).profile, same(original));
      expect(editor.state.avatar, same(photo));
      expect(draft.changes, {'bio': 'Keep this draft'});
      expect(api.patchBody, isNull);
      expect(await editor.save(draft), false);
      expect(storage.requests, 1);
      expect(api.calls.where((e) => e.startsWith('POST')), [
        'POST media/presign',
      ]);
      expect(editor.state.avatar, same(photo));
      // Only an authoritative server ready result permits claiming this ID.
      api.statuses = ['ready'];
      expect(await editor.save(draft), true);
      expect(api.patchBody, {'bio': 'Keep this draft', 'avatar_media_id': 19});
      expect(storage.requests, 1);
      expect(api.calls.where((e) => e.contains('finalize')), isEmpty);
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
      final service = MediaUploadService(
        api: api,
        storageAdapter: storage,
        now: () => DateTime.utc(2026),
        wait: (_) async {},
      );
      final owner = ProfileCubit(profileRepo: ProfileRepo(apiService: api));
      await owner.loadProfile();
      final original = (owner.state as ProfileLoaded).profile;
      final editor = EditProfileCubit(
        owner,
        avatarRepo: Photos(),
        mediaUpload: service,
      );
      addTearDown(() async {
        await editor.close();
        await owner.close();
        service.close();
      });
      await editor.pickAvatar();
      final photo = editor.state.avatar;
      final draft = ProfileDraft(original)..set('bio', 'Keep edits');
      expect(await editor.save(draft), false);
      expect(editor.state.avatar, same(photo));
      expect(draft.changes, {'bio': 'Keep edits'});
      expect(api.patchBody, isNull);
      expect(await editor.save(draft), true);
      expect(api.patchBody, {'bio': 'Keep edits', 'avatar_media_id': 19});
      expect(storage.requests, 1);
      expect(api.calls.where((c) => c == 'POST media/presign'), hasLength(1));
      expect(api.calls.where((c) => c.contains('finalize')), hasLength(1));
      expect(api.calls.last, 'GET profile');
      expect(
        (owner.state as ProfileLoaded).profile.avatarUrl,
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
      final service = MediaUploadService(
        api: api,
        storageAdapter: storage,
        now: () => DateTime.utc(2026),
        wait: (_) async {},
      );
      final owner = ProfileCubit(profileRepo: ProfileRepo(apiService: api));
      await owner.loadProfile();
      final editor = EditProfileCubit(
        owner,
        avatarRepo: Photos(),
        mediaUpload: service,
      );
      addTearDown(() async {
        await editor.close();
        await owner.close();
        service.close();
      });
      await editor.pickAvatar();
      expect(
        await editor.save(ProfileDraft((owner.state as ProfileLoaded).profile)),
        true,
      );
      expect(api.patchBody, {'avatar_media_id': 19});
      expect(api.calls.where((c) => c.contains('finalize')), [
        'POST media/19/finalize',
      ]);
      expect(storage.requests, 1);
      expect(api.calls.last, 'GET profile');
      expect(
        (owner.state as ProfileLoaded).profile.avatarUrl,
        'https://example.invalid/new-avatar.png',
      );
    },
  );

  test(
    'finalize 422 preserves existing profile, selected image, fields and validation error',
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
      final service = MediaUploadService(
        api: api,
        storageAdapter: storage,
        now: () => DateTime.utc(2026),
        wait: (_) async {},
      );
      final owner = ProfileCubit(profileRepo: ProfileRepo(apiService: api));
      await owner.loadProfile();
      final original = (owner.state as ProfileLoaded).profile;
      final editor = EditProfileCubit(
        owner,
        avatarRepo: Photos(),
        mediaUpload: service,
      );
      addTearDown(() async {
        await editor.close();
        await owner.close();
        service.close();
      });
      await editor.pickAvatar();
      final photo = editor.state.avatar;
      final draft = ProfileDraft(original)..set('bio', 'Keep my changes');
      expect(await editor.save(draft), false);
      expect(editor.state.error, same(validation));
      expect(editor.state.avatar, same(photo));
      expect(draft.changes, {'bio': 'Keep my changes'});
      expect((owner.state as ProfileLoaded).profile, same(original));
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
      final service = MediaUploadService(
        api: api,
        storageAdapter: storage,
        now: () => DateTime.utc(2026),
        wait: (_) async {},
      );
      final owner = ProfileCubit(profileRepo: ProfileRepo(apiService: api));
      await owner.loadProfile();
      final original = (owner.state as ProfileLoaded).profile;
      final editor = EditProfileCubit(
        owner,
        avatarRepo: Photos(),
        mediaUpload: service,
      );
      addTearDown(() async {
        await editor.close();
        await owner.close();
        service.close();
      });
      await editor.pickAvatar();
      final photo = editor.state.avatar;
      final draft = ProfileDraft(original)..set('bio', 'Unsaved');
      expect(await editor.save(draft), false);
      expect(api.patchBody, isNull);
      expect((owner.state as ProfileLoaded).profile, same(original));
      expect(editor.state.avatar, same(photo));
      api.statuses = ['ready'];
      api.patchError = ApiError(message: 'Invalid', statusCode: 422);
      expect(await editor.save(draft), false);
      expect(storage.requests, 2);
      api.patchError = null;
      expect(await editor.save(draft), true);
      expect(storage.requests, 2);
      expect(api.patchBody, {'bio': 'Unsaved', 'avatar_media_id': 19});
    },
  );
}
