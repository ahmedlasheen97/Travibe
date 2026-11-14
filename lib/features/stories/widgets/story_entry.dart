import 'package:travibe/features/stories/data/stories_repo.dart';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:travibe/features/stories/cubit/story_picker_cubit.dart';
import 'package:travibe/features/stories/cubit/story_upload_cubit.dart';
import 'package:travibe/features/stories/data/story_editor_draft.dart';
import 'package:travibe/features/stories/data/story_photo_repo.dart';
import 'package:travibe/features/stories/screens/story_editor_screen.dart';
import 'package:travibe/features/stories/widgets/post_story_sheet.dart';

/// Owns the local selection flow without changing Home's feed or navigation.
class StoryEntry extends StatefulWidget {
  const StoryEntry({
    super.key,
    required this.builder,
    this.repo,
    this.avatarUrl,
    this.storiesRepo,
    this.onPublished,
    this.onSubmit,
  });

  final Widget Function(BuildContext context, VoidCallback onAddStory) builder;
  final StoryPhotoRepo? repo;
  final String? avatarUrl;
  final StoriesRepo? storiesRepo;
  final Future<void> Function()? onPublished;

  /// Background publishing; see [StoryEditorScreen.onSubmit].
  final ValueChanged<StoryUploadJob>? onSubmit;

  @override
  State<StoryEntry> createState() => _StoryEntryState();
}

class _StoryEntryState extends State<StoryEntry> {
  late final _picker = StoryPickerCubit(repo: widget.repo);
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      _opening = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _recover());
    }
  }

  Future<void> _recover() async {
    if (!mounted) return;
    try {
      final draft = await _picker.recover();
      if (!mounted) return;
      if (draft != null) {
        await _openEditor(draft);
      } else if (_picker.state.error != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_picker.state.error!)));
      }
    } finally {
      _opening = false;
    }
  }

  Future<void> _open() async {
    if (_opening) return;
    _opening = true;
    try {
      final draft = await PostStorySheet.show(context, _picker);
      if (mounted && draft != null) await _openEditor(draft);
    } finally {
      _opening = false;
    }
  }

  Future<void> _openEditor(StoryEditorDraft draft) =>
      Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => StoryEditorScreen(
            draft: draft,
            avatarUrl: widget.avatarUrl,
            storiesRepo: widget.storiesRepo,
            onPublished: widget.onPublished,
            onSubmit: widget.onSubmit,
          ),
        ),
      );

  @override
  void dispose() {
    unawaited(_picker.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _open);
}
