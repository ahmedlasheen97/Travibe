import 'package:travibe/core/widgets/app_loaders.dart';
import 'package:travibe/core/widgets/back_button_widget.dart';
import 'package:travibe/features/stories/cubit/story_publish_cubit.dart';
import 'package:travibe/features/stories/data/stories_repo.dart';
import 'package:travibe/core/media/media_upload_service.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:travibe/features/stories/data/story_audience.dart';
import 'package:travibe/features/stories/data/story_editor_draft.dart';
import 'package:travibe/features/stories/cubit/story_editor_cubit.dart';
import 'package:travibe/features/stories/widgets/story_canvas.dart';
import 'package:travibe/features/stories/widgets/story_text_entry.dart';
import 'package:travibe/features/stories/widgets/story_audience_sheet.dart';

class StoryEditorScreen extends StatefulWidget {
  const StoryEditorScreen({
    super.key,
    required this.draft,
    this.avatarUrl,
    this.storiesRepo,
    this.uploads,
    this.onPublished,
  });

  final StoryEditorDraft draft;
  final String? avatarUrl;
  final StoriesRepo? storiesRepo;
  final MediaUploadService? uploads;
  final Future<void> Function()? onPublished;

  @override
  State<StoryEditorScreen> createState() => _StoryEditorScreenState();
}

class _StoryEditorScreenState extends State<StoryEditorScreen> {
  late final _editor = StoryEditorCubit(widget.draft);
  final _export = StoryExportController();
  late final _publisher = StoryPublishCubit(
    repo: widget.storiesRepo,
    uploads: widget.uploads,
    onPublished: widget.onPublished,
  );

  void _post() {
    if (_enteringText ||
        _selectingAudience ||
        _publisher.state.busy ||
        _export.isInteracting) {
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    _publisher.publish(_editor.state);
  }

  bool _enteringText = false;
  bool _selectingAudience = false;

  Future<void> _editText([StoryTextLayer? layer]) async {
    if (_enteringText || _selectingAudience || _publisher.state.busy) return;
    if (layer == null && _editor.state.layers.length >= 50) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('A Story can contain at most 50 text elements.'),
        ),
      );
      return;
    }
    _enteringText = true;
    try {
      final text = await showStoryTextEntry(context, text: layer?.text);
      if (mounted && text != null) _editor.saveText(text, id: layer?.id);
    } finally {
      _enteringText = false;
    }
  }

  Future<void> _selectAudience() async {
    if (_selectingAudience || _enteringText || _publisher.state.busy) return;
    _selectingAudience = true;
    try {
      final selected = await showStoryAudienceSheet(
        context,
        selected: _editor.state.audience,
      );
      if (mounted && selected != null) _editor.setAudience(selected);
    } finally {
      _selectingAudience = false;
    }
  }

  @override
  void dispose() {
    _publisher.close();
    _editor.close();
    super.dispose();
  }

  @override
  Widget build(
    BuildContext context,
  ) => BlocConsumer<StoryPublishCubit, StoryPublishState>(
    bloc: _publisher,
    listener: (context, state) {
      if (state.error != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(state.error!.message)));
      } else if (state.status == StoryPublishStatus.success) {
        // A host with onPublished (Home) shows its own floating toast.
        if (widget.onPublished == null) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Story published')));
        }
        Navigator.of(context).pop();
      }
    },
    builder: (context, publishing) => PopScope(
      canPop: !publishing.busy,
      child: AbsorbPointer(
        absorbing: publishing.busy,
        child: Scaffold(
          backgroundColor: Colors.black,
          resizeToAvoidBottomInset: false,
          body: SafeArea(
            bottom: false,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Keep the same full viewport and crop for both image and text geometry.
                BlocBuilder<StoryEditorCubit, StoryEditorDraft>(
                  bloc: _editor,
                  builder: (context, draft) => StoryCanvas(
                    draft: draft,
                    exportController: _export,
                    onEditText: _editText,
                    onTransform: _editor.commitTransform,
                    onDelete: _editor.removeLayer,
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 20, 20, 12),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            BackButtonWidget(
                              key: const ValueKey('story-back'),
                              onTap: () => Navigator.pop(context),
                              size: 44,
                              iconSize: 20,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  // Normal size is 140x44. Scale down only when large
                                  // accessibility text leaves less header space.
                                  Flexible(
                                    child:
                                        BlocSelector<
                                          StoryEditorCubit,
                                          StoryEditorDraft,
                                          StoryAudience
                                        >(
                                          bloc: _editor,
                                          selector: (draft) => draft.audience,
                                          builder: (context, audience) =>
                                              FittedBox(
                                                fit: BoxFit.scaleDown,
                                                child: _StoryAudienceControl(
                                                  audience: audience,
                                                  onPressed: _selectAudience,
                                                ),
                                              ),
                                        ),
                                  ),
                                  const SizedBox(width: 8),
                                  BlocBuilder<
                                    StoryEditorCubit,
                                    StoryEditorDraft
                                  >(
                                    bloc: _editor,
                                    builder: (context, draft) => Tooltip(
                                      message: 'Publish Story',
                                      child: FilledButton(
                                        key: const ValueKey('story-post'),
                                        onPressed:
                                            publishing.busy ||
                                                publishing.uncertain ||
                                                publishing.sessionEnded ||
                                                !PreferencesManager().hasSession
                                            ? null
                                            : _post,
                                        style: FilledButton.styleFrom(
                                          backgroundColor:
                                              DarkColors.primaryColor,
                                          foregroundColor: Colors.white,
                                          disabledBackgroundColor:
                                              DarkColors.primaryColor,
                                          disabledForegroundColor: Colors.white,
                                          minimumSize: const Size(80, 44),
                                          visualDensity: VisualDensity.standard,
                                          tapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                          shape: const StadiumBorder(),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 10,
                                          ),
                                          textStyle: const TextStyle(
                                            fontFamily: 'Plus Jakarta Sans',
                                            fontSize: 18,
                                            height: 24 / 18,
                                            fontWeight: FontWeight.w500,
                                            letterSpacing: 0,
                                          ),
                                        ),
                                        child: publishing.busy
                                            ? SizedBox.square(
                                                dimension: 20,
                                                child: Semantics(
                                                  label: publishing.progress,
                                                  liveRegion: true,
                                                  child:
                                                      const AppActivityIndicator(
                                                        key: ValueKey(
                                                          'story-post-progress',
                                                        ),
                                                        radius: 10,
                                                      ),
                                                ),
                                              )
                                            : const Text('Post'),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 26),
                        Expanded(
                          child: Align(
                            alignment: Alignment.topRight,
                            child: SingleChildScrollView(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _tool(
                                    'Text',
                                    text: 'Aa',
                                    onPressed: _editText,
                                  ),
                                  _tool('Mention', icon: Icons.alternate_email),
                                  _tool(
                                    'Sticker / Emoji',
                                    icon: Icons.sentiment_satisfied_outlined,
                                  ),
                                  _tool('Draw', icon: Icons.edit_outlined),
                                  _tool(
                                    'Location',
                                    icon: Icons.location_on_outlined,
                                    last: true,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  ButtonStyle _circleStyle(Color background) => IconButton.styleFrom(
    backgroundColor: background,
    disabledBackgroundColor: background,
    foregroundColor: Colors.white,
    disabledForegroundColor: Colors.white,
    fixedSize: const Size(44, 44),
    padding: EdgeInsets.zero,
    visualDensity: VisualDensity.standard,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    shape: const CircleBorder(),
  );

  Widget _tool(
    String label, {
    IconData? icon,
    String? text,
    VoidCallback? onPressed,
    bool last = false,
  }) => Padding(
    padding: EdgeInsets.only(bottom: last ? 0 : 16),
    child: IconButton.filled(
      key: onPressed != null ? const ValueKey('story-text-tool') : null,
      tooltip: onPressed != null ? 'Add text' : '$label — coming soon',
      onPressed: onPressed,
      style: _circleStyle(const Color(0xCC45433B)),
      icon: text != null
          ? Text(
              text,
              style: const TextStyle(
                color: Colors.white,
                fontFamily: 'Plus Jakarta Sans',
                fontSize: 14,
                fontWeight: FontWeight.w500,
                letterSpacing: 0,
              ),
            )
          : Icon(icon, size: 24),
    ),
  );
}

class _StoryAudienceControl extends StatelessWidget {
  const _StoryAudienceControl({
    required this.audience,
    required this.onPressed,
  });
  final StoryAudience audience;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0xFF2F2E2D),
    borderRadius: BorderRadius.circular(28),
    child: InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(28),
      child: Semantics(
        label: 'Story audience: ${audience.label}',
        button: true,
        excludeSemantics: true,
        child: Container(
          key: const ValueKey('story-audience'),
          width: audience == StoryAudience.public ? 140 : 156,
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Icon(
                audience == StoryAudience.public
                    ? Icons.language
                    : Icons.people_outline,
                color: Colors.white,
                size: 24,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  audience.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontFamily: 'Plus Jakarta Sans',
                    fontSize: 18,
                    height: 24 / 18,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              const Icon(
                Icons.keyboard_arrow_down,
                color: Colors.white,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
