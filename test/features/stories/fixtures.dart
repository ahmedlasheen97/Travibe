import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'package:travibe/features/stories/data/story_editor_draft.dart';
import 'package:travibe/features/stories/data/story_photo_repo.dart';

Uint8List photoBytes() => base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAQAAAACCAYAAAB/qH1jAAAAEklEQVR4nGP43+DwHxkzoAsAAHYhFfF34aTLAAAAAElFTkSuQmCC',
);

StoryEditorDraft draft() => StoryEditorDraft(
  image: StorySourceImage(
    path: '/local/photo.png',
    name: 'photo.png',
    width: 4,
    height: 2,
    bytes: photoBytes(),
  ),
);

class MemoryPendingStore implements StoryPendingSelectionStore {
  bool pending = false;
  @override
  Future<bool> get isPending async => pending;
  @override
  Future<void> setPending(bool value) async {
    pending = value;
  }
}

class SpyImagePicker extends ImagePicker {
  XFile? result;
  Object? error;
  Completer<XFile?>? completer;
  int picks = 0;
  int recoveries = 0;
  ImageSource? source;
  bool? fullMetadata;
  double? width;
  double? height;
  int? quality;
  void Function()? onPick;
  LostDataResponse lost = LostDataResponse.empty();

  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async {
    picks++;
    this.source = source;
    fullMetadata = requestFullMetadata;
    width = maxWidth;
    height = maxHeight;
    quality = imageQuality;
    onPick?.call();
    if (error != null) throw error!;
    if (completer != null) return completer!.future;
    return result;
  }

  @override
  Future<LostDataResponse> retrieveLostData() async {
    recoveries++;
    return lost;
  }
}

class StubStoryPhotoRepo extends StoryPhotoRepo {
  StoryEditorDraft? selected;
  StoryEditorDraft? recovered;
  Object? failure;
  Object? recoveryFailure;
  Completer<StoryEditorDraft?>? selection;
  int picks = 0;
  int captures = 0;
  int recoveries = 0;

  @override
  Future<StoryEditorDraft?> pick() async {
    picks++;
    if (failure != null) throw failure!;
    if (selection != null) return selection!.future;
    return selected;
  }

  @override
  Future<StoryEditorDraft?> capture() async {
    captures++;
    if (failure != null) throw failure!;
    if (selection != null) return selection!.future;
    return selected;
  }

  @override
  Future<StoryEditorDraft?> recover() async {
    recoveries++;
    if (recoveryFailure != null) throw recoveryFailure!;
    return recovered;
  }
}

/// The hidden-mentions element older builds sent (before `mention_user_ids`).
/// The API now returns its `text` exactly as sent: `"​"`.
Map<String, dynamic> legacyMentionsElement(
  List<StoryMentionedUser> mentions, {
  Object? text = '​',
}) => {
  'version': 1,
  'id': 'story-mentions',
  'type': 'text',
  'text': text,
  'content': mentions.map((m) => '@${m.username}').join(' '),
  'position': {'x': 0.5, 'y': 0.5},
  'scale': 1,
  'style': {
    'font_family': 'Plus Jakarta Sans',
    'font_size': 24,
    'reference_width': 390,
    'font_weight': 600,
    'color_argb': 0xFFFFFFFF,
    'shadow_color_argb': 0xDD000000,
    'shadow_blur': 3,
    'padding': 8,
    'max_width_fraction': 0.8,
    'alignment': 'center',
    'direction': 'ltr',
  },
  'mentions': [
    for (final m in mentions) {'user_id': m.id, 'username': m.username},
  ],
};
