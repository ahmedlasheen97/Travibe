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
  bool avatarSaved = false;
  @override
  Future<dynamic> patch(String endpoint, Map<String, dynamic> data) async {
    calls.add('PATCH $endpoint');
    expect(endpoint, 'profile');
    if (patchError != null) throw patchError!;
    patchBody = data;
    avatarSaved |= data.containsKey('avatar_media_id');
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
          'avatar_url': !avatarSaved
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

  /// Picks a photo and waits for its background upload (no profile write).
  Future<void> pickAndSettle(_Rig r) async {
    await r.editor.pickAvatar();
    if (r.pictures.uploading) {
      await r.pictures.stream.firstWhere((s) => s is! ProfilePictureUploading);
    }
  }

  /// What Edit Profile does when the upload finishes: the picture becomes a
  /// pending form change.
  ProfileDraft draftFor(_Rig r, {String? bio}) {
    final draft = ProfileDraft((r.owner.state as ProfileLoaded).profile);
    if (bio != null) draft.set('bio', bio);
    draft.set('avatar_media_id', r.pictures.mediaId);
    return draft;
  }

  String? avatarOf(_Rig r) =>
      (r.owner.state as ProfileLoaded).profile.avatarUrl;

  test(
    'pick only uploads; Save Changes sends the picture with the other fields',
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
      expect(r.pictures.state, isA<ProfilePictureDone>());
      expect(r.pictures.mediaId, 19);
      // Nothing is attached until Save Changes.
      expect(api.patchBody, isNull);
      expect(avatarOf(r), isNull);
      expect(api.calls, [
        'GET profile',
        'POST media/presign',
        'PUT storage',
        'POST media/19/finalize',
        'GET media/19',
        'GET media/19',
        'GET media/19',
      ]);
      final draft = draftFor(r, bio: 'New bio');
      expect(await r.editor.save(draft), true);
      expect(api.patchBody, {'bio': 'New bio', 'avatar_media_id': 19});
      expect(api.calls.where((c) => c == 'PATCH profile'), hasLength(1));
      expect(avatarOf(r), 'https://example.invalid/new-avatar.png');
      expect((r.owner.state as ProfileLoaded).profile.bio, 'New bio');
      expect(r.editor.state.saved, true);
      expect(draft.isDirty, false);
    },
  );

  test(
    'ambiguous storage timeout keeps the preview; other fields still save without it; Retry reconciles without writes',
    () async {
      final api = PipelineApi()..statuses = ['pending'];
      final storage = StorageAdapter()..receiveTimeout = true;
      final r = await rig(api, storage);
      await pickAndSettle(r);
      expect(r.pictures.state, isA<ProfilePictureFailed>());
      expect(r.pictures.state.preview, r.source.bytes);
      final draft = draftFor(r, bio: 'Keep this draft');
      expect(draft.changes, {'bio': 'Keep this draft'});
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
      expect(api.patchBody, isNull);
      expect(storage.requests, 1);
      expect(api.calls.where((e) => e.contains('finalize')), isEmpty);
      draft.set('avatar_media_id', r.pictures.mediaId);
      expect(await r.editor.save(draft), true);
      expect(api.patchBody, {'bio': 'Keep this draft', 'avatar_media_id': 19});
    },
  );

  test(
    'observed top-level media ready response recovers failed finalize parsing without another upload',
    () async {
      final api = PipelineApi()
        ..finalizeResponse = {'unexpected': {}}
        ..statusEnvelope = 'media'
        ..statuses = ['ready'];
      final storage = StorageAdapter();
      final r = await rig(api, storage);
      await pickAndSettle(r);
      expect(r.pictures.state, isA<ProfilePictureFailed>());
      await r.pictures.retry();
      expect(r.pictures.mediaId, 19);
      expect(api.patchBody, isNull);
      expect(storage.requests, 1);
      expect(api.calls.where((c) => c == 'POST media/presign'), hasLength(1));
      expect(api.calls.where((c) => c.contains('finalize')), hasLength(1));
      expect(await r.editor.save(draftFor(r)), true);
      expect(api.patchBody, {'avatar_media_id': 19});
      expect(api.calls.last, 'GET profile');
      expect(avatarOf(r), 'https://example.invalid/new-avatar.png');
    },
  );

  test('finalize 409 reconciles ready media; Save attaches it', () async {
    final api = PipelineApi()
      ..finalizeError = ApiError(message: 'Already finalized', statusCode: 409)
      ..statuses = ['processing', 'ready'];
    final storage = StorageAdapter();
    final r = await rig(api, storage);
    await pickAndSettle(r);
    expect(r.pictures.mediaId, 19);
    expect(api.patchBody, isNull);
    expect(api.calls.where((c) => c.contains('finalize')), [
      'POST media/19/finalize',
    ]);
    expect(storage.requests, 1);
    expect(await r.editor.save(draftFor(r)), true);
    expect(api.patchBody, {'avatar_media_id': 19});
    expect(avatarOf(r), 'https://example.invalid/new-avatar.png');
  });

  test(
    'finalize 422 fails the picture; Save keeps the old picture and saves the fields',
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
      await pickAndSettle(r);
      expect(r.pictures.state, isA<ProfilePictureFailed>());
      expect(r.pictures.state.preview, r.source.bytes);
      expect(api.calls.where((c) => c.startsWith('GET media')), isEmpty);
      expect(storage.requests, 1);
      expect(await r.editor.save(draftFor(r, bio: 'Keep my changes')), true);
      expect(api.patchBody, {'bio': 'Keep my changes'});
      expect(avatarOf(r), isNull);
    },
  );

  test(
    'failed processing never writes the profile; a Save PATCH error reuses the ready media',
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
      await r.pictures.retry();
      expect(r.pictures.mediaId, 19);
      expect(storage.requests, 2);
      final draft = draftFor(r);
      api.patchError = ApiError(message: 'Invalid', statusCode: 422);
      expect(await r.editor.save(draft), false);
      expect(draft.changes, {'avatar_media_id': 19});
      api.patchError = null;
      expect(await r.editor.save(draft), true);
      expect(storage.requests, 2);
      expect(api.patchBody, {'avatar_media_id': 19});
    },
  );
}
