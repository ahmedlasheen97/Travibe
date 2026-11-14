import 'package:travibe/core/widgets/app_loaders.dart';
import 'package:travibe/core/widgets/travibe_toast.dart';
import 'package:travibe/features/stories/cubit/story_upload_cubit.dart';
import 'package:travibe/features/stories/data/story_elements.dart';
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
import 'package:travibe/features/stories/widgets/story_image_exporter.dart';
import 'package:travibe/features/stories/widgets/story_text_entry.dart';
import 'package:travibe/features/stories/widgets/story_audience_sheet.dart';
import 'package:travibe/features/stories/widgets/story_emoji_sheet.dart';
import 'package:travibe/features/stories/widgets/story_mention_sheet.dart';
import 'package:travibe/features/search/data/search_repo.dart';

/// Draw-mode palette: white, black, orange, red, yellow, green, blue.
abstract final class StoryEditorScreenColors {
  static const brush = <Color>[
    Colors.white,
    Colors.black,
    DarkColors.primaryColor,
    Color(0xFFE53935),
    Color(0xFFFDD835),
    Color(0xFF43A047),
    Color(0xFF1E88E5),
  ];
}

class StoryEditorScreen extends StatefulWidget {
  const StoryEditorScreen({
    super.key,
    required this.draft,
    this.avatarUrl,
    this.storiesRepo,
    this.uploads,
    this.searchRepo,
    this.onPublished,
    this.onSubmit,
    this.exporter,
  });

  final StoryEditorDraft draft;
  final String? avatarUrl;
  final StoriesRepo? storiesRepo;
  final MediaUploadService? uploads;

  /// User search for the @ Mention sheet; defaults to the real API.
  final SearchRepo? searchRepo;
  final Future<void> Function()? onPublished;

  /// Background publishing (Home): Post hands the Story over and the editor
  /// closes at once; the host shows progress. Without it the editor publishes
  /// in place (isolated use and tests).
  final ValueChanged<StoryUploadJob>? onSubmit;

  /// In-place publishing only; defaults to the JPEG exporter.
  final StoryImageExporter? exporter;

  @override
  State<StoryEditorScreen> createState() => _StoryEditorScreenState();
}

class _StoryEditorScreenState extends State<StoryEditorScreen> {
  late final _editor = StoryEditorCubit(widget.draft);
  final _export = StoryExportController();
  late final _publisher = StoryPublishCubit(
    repo: widget.storiesRepo,
    uploads: widget.uploads,
    exporter: widget.exporter,
    onPublished: widget.onPublished,
  );

  void _post() {
    if (_sheetOpen ||
        _drawing ||
        _publisher.state.busy ||
        _export.isInteracting) {
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    final submit = widget.onSubmit;
    if (submit == null) {
      _publisher.publish(_editor.state, viewport: _export.viewportSize);
      return;
    }
    try {
      StoryElements.encode(_editor.state.layers);
    } on FormatException catch (e) {
      TravibeToast.show(context, TravibeToastData.error(e.message));
      return;
    }
    submit(
      StoryUploadJob(draft: _editor.state, viewport: _export.viewportSize),
    );
    Navigator.of(context).pop();
  }

  bool _enteringText = false;
  bool _selectingAudience = false;
  bool _pickingSticker = false;
  bool get _sheetOpen => _enteringText || _selectingAudience || _pickingSticker;

  // Drawing mode state. Brush width is in logical pixels at the canvas width.
  bool _drawing = false;
  Color _brushColor = Colors.white;
  double _brushWidth = 6;

  void _snack(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  Future<void> _addMention() async {
    if (_sheetOpen || _drawing || _publisher.state.busy) return;
    if (_editor.elementCount >= StoryEditorCubit.maxElements) {
      _snack('A Story can contain at most 50 text elements.');
      return;
    }
    _pickingSticker = true;
    try {
      final user = await showStoryMentionSheet(
        context,
        repo: widget.searchRepo,
      );
      if (mounted && user != null && !_editor.addMention(user)) {
        _snack('This person can\'t be mentioned.');
      }
    } finally {
      _pickingSticker = false;
    }
  }

  Future<void> _addEmoji() async {
    if (_sheetOpen || _drawing || _publisher.state.busy) return;
    if (_editor.emojiCount >= StoryEditorCubit.maxEmojis) {
      _snack('A Story can contain at most 30 emojis.');
      return;
    }
    _pickingSticker = true;
    try {
      final emoji = await showStoryEmojiSheet(context);
      if (mounted && emoji != null) _editor.addEmoji(emoji);
    } finally {
      _pickingSticker = false;
    }
  }

  void _setDrawing(bool drawing) {
    if (drawing &&
        (_sheetOpen || _publisher.state.busy || _export.isInteracting)) {
      return;
    }
    setState(() => _drawing = drawing);
  }

  Future<void> _editText([StoryTextLayer? layer]) async {
    if (_sheetOpen || _drawing || _publisher.state.busy) return;
    if (layer == null && _editor.elementCount >= StoryEditorCubit.maxElements) {
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
    if (_sheetOpen || _drawing || _publisher.state.busy) return;
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
        // Plain wording only; the cubit never surfaces transport details.
        TravibeToast.show(
          context,
          TravibeToastData.error(state.error!.message),
        );
      } else if (state.status == StoryPublishStatus.success) {
        // A host with onPublished (Home) shows its own floating toast.
        if (widget.onPublished == null) {
          TravibeToast.show(
            context,
            const TravibeToastData.success('Story published successfully'),
          );
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
                    onTransformLayer: (id, center, scale, rotation) => _editor
                        .commitTransform(id, center, scale, rotation: rotation),
                    onCycleMentionStyle: _editor.cycleMentionStyle,
                    onDelete: _editor.removeLayer,
                    drawing: _drawing,
                    brushColor: _brushColor,
                    brushWidth: _brushWidth,
                    onStroke: _editor.addStroke,
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 20, 20, 12),
                    child: Column(
                      children: [
                        if (_drawing)
                          _drawHeader()
                        else
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
                                                  publishing.sessionEnded ||
                                                  !PreferencesManager()
                                                      .hasSession
                                              ? null
                                              : _post,
                                          style: FilledButton.styleFrom(
                                            backgroundColor:
                                                DarkColors.primaryColor,
                                            foregroundColor: Colors.white,
                                            disabledBackgroundColor:
                                                DarkColors.primaryColor,
                                            disabledForegroundColor:
                                                Colors.white,
                                            minimumSize: const Size(80, 44),
                                            visualDensity:
                                                VisualDensity.standard,
                                            tapTargetSize: MaterialTapTargetSize
                                                .shrinkWrap,
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
                          child: _drawing
                              ? Align(
                                  alignment: Alignment.bottomCenter,
                                  child: _drawControls(),
                                )
                              : Align(
                                  alignment: Alignment.topRight,
                                  child: SingleChildScrollView(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        _tool(
                                          'story-text-tool',
                                          'Add text',
                                          text: 'Aa',
                                          onPressed: _editText,
                                        ),
                                        _tool(
                                          'story-mention-tool',
                                          'Mention someone',
                                          icon: Icons.alternate_email,
                                          onPressed: _addMention,
                                        ),
                                        _tool(
                                          'story-emoji-tool',
                                          'Add emoji',
                                          icon: Icons
                                              .sentiment_satisfied_outlined,
                                          onPressed: _addEmoji,
                                        ),
                                        _tool(
                                          'story-draw-tool',
                                          'Draw',
                                          icon: Icons.edit_outlined,
                                          onPressed: () => _setDrawing(true),
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
    String key,
    String tooltip, {
    IconData? icon,
    String? text,
    required VoidCallback onPressed,
    bool last = false,
  }) => Padding(
    padding: EdgeInsets.only(bottom: last ? 0 : 16),
    child: IconButton.filled(
      key: ValueKey(key),
      tooltip: tooltip,
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

  static const _drawLabel = TextStyle(
    fontFamily: 'Plus Jakarta Sans',
    fontSize: 16,
    fontWeight: FontWeight.w500,
    letterSpacing: 0,
  );

  /// Replaces Back/audience/Post while drawing: Undo on the left, Done right.
  Widget _drawHeader() =>
      BlocSelector<StoryEditorCubit, StoryEditorDraft, bool>(
        bloc: _editor,
        selector: (draft) => draft.strokes.isNotEmpty,
        builder: (context, canUndo) => Row(
          children: [
            IconButton.filled(
              key: const ValueKey('story-draw-undo'),
              tooltip: 'Undo last stroke',
              onPressed: canUndo ? _editor.undoStroke : null,
              style: _circleStyle(const Color(0xCC45433B)),
              icon: Icon(
                Icons.undo,
                size: 22,
                color: canUndo ? Colors.white : Colors.white38,
              ),
            ),
            const Spacer(),
            FilledButton(
              key: const ValueKey('story-draw-done'),
              onPressed: () => _setDrawing(false),
              style: FilledButton.styleFrom(
                backgroundColor: DarkColors.primaryColor,
                foregroundColor: Colors.white,
                minimumSize: const Size(80, 44),
                shape: const StadiumBorder(),
                textStyle: _drawLabel,
              ),
              child: const Text('Done'),
            ),
          ],
        ),
      );

  Widget _drawControls() => Container(
    key: const ValueKey('story-draw-controls'),
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
    decoration: BoxDecoration(
      color: const Color(0x99000000),
      borderRadius: BorderRadius.circular(24),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            const Icon(Icons.circle, size: 8, color: Colors.white70),
            Expanded(
              child: Slider(
                key: const ValueKey('story-brush-size'),
                min: 2,
                max: 24,
                value: _brushWidth,
                activeColor: Colors.white,
                inactiveColor: Colors.white24,
                thumbColor: _brushColor,
                semanticFormatterCallback: (value) =>
                    'Brush size ${value.round()}',
                onChanged: (value) => setState(() => _brushWidth = value),
              ),
            ),
            const Icon(Icons.circle, size: 20, color: Colors.white70),
          ],
        ),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            children: [
              for (final color in StoryEditorScreenColors.brush)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  child: Semantics(
                    button: true,
                    selected: color == _brushColor,
                    label: 'Brush color',
                    child: GestureDetector(
                      key: ValueKey('story-brush-${color.toARGB32()}'),
                      onTap: () => setState(() => _brushColor = color),
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: color == _brushColor
                                ? Colors.white
                                : Colors.white38,
                            width: color == _brushColor ? 3 : 1.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
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
