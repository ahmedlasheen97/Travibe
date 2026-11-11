import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:geolocator/geolocator.dart';
import 'package:travibe/features/profile/cubit/current_user_cubit.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:travibe/features/create_post/cubit/create_post_cubit.dart';
import 'package:travibe/features/create_post/data/create_post_repo.dart';
import 'package:travibe/features/create_post/data/create_post_request.dart';
import 'package:travibe/features/create_post/data/post_image.dart';
import 'package:travibe/features/create_post/data/post_image_picker.dart';
import 'package:travibe/features/chats/widgets/chat_emoji_picker.dart';
import 'package:travibe/features/create_post/widgets/audience_sheet.dart';
import 'package:travibe/features/create_post/widgets/create_post_styles.dart';
import 'package:travibe/features/create_post/widgets/discard_post_dialog.dart';
import 'package:travibe/features/home/data/post_model.dart';

/// Composes a post and returns it as a draft; `PostUploadCubit` publishes it
/// in the background after this screen has closed.
class CreatePostScreen extends StatelessWidget {
  const CreatePostScreen({super.key, this.repo, this.picker});
  final CreatePostRepo? repo;
  final PostImagePicker? picker;

  static Future<CreatePostRequest?> open(
    BuildContext context, {
    CreatePostRepo? repo,
    PostImagePicker? picker,
  }) => Navigator.of(context).push<CreatePostRequest>(
    MaterialPageRoute(
      builder: (_) => CreatePostScreen(repo: repo, picker: picker),
    ),
  );

  /// The app-wide current user, when already loaded, as the post author.
  static PostAuthorModel? _cachedAuthor(BuildContext context) {
    final profile = context.read<CurrentUserCubit?>()?.state.profile;
    if (profile == null || profile.displayName.isEmpty) return null;
    return PostAuthorModel(
      id: profile.id,
      name: profile.displayName,
      username: profile.username,
      avatarUrl: profile.avatarUrl,
      isFollowing: false,
      isBlocked: false,
      followersCount: 0,
      followingCount: 0,
    );
  }

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (context) =>
        CreatePostCubit(repo: repo, initialAuthor: _cachedAuthor(context))
          ..loadAuthor(),
    child: _Composer(picker: picker ?? PostImagePicker()),
  );
}

class _Composer extends StatefulWidget {
  const _Composer({required this.picker});
  final PostImagePicker picker;
  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer> {
  final _text = TextEditingController();
  final _focus = FocusNode();
  bool _allowPop = false;
  bool _confirmingClose = false;
  bool _picking = false;
  bool _showEmoji = false;

  @override
  void initState() {
    super.initState();
    // Sync from the controller, not onChanged, so IME composition,
    // autocorrect, paste and emoji insertion all reach the cubit.
    _text.addListener(_syncText);
  }

  void _syncText() {
    final cubit = context.read<CreatePostCubit>();
    if (cubit.state.content != _text.text) cubit.setContent(_text.text);
  }

  /// The field is the source of truth for text; the cubit for photos.
  bool get _hasUnsavedContent =>
      _text.text.isNotEmpty ||
      context.read<CreatePostCubit>().state.hasUnsavedContent;

  @override
  void dispose() {
    _text.removeListener(_syncText);
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _publish() async {
    final request = context.read<CreatePostCubit>().state.request;
    if (request.validationError != null || _allowPop) return;
    setState(() => _allowPop = true);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.pop(context, request);
  }

  Future<void> _addImages({required bool camera}) async {
    final cubit = context.read<CreatePostCubit>();
    if (_picking) return;
    if (cubit.state.remainingImages <= 0) {
      cubit.notifyLimit();
      return;
    }
    _picking = true;
    FocusScope.of(context).unfocus();
    try {
      final pick = camera
          ? await widget.picker.capture()
          : await widget.picker.pickGallery(limit: cubit.state.remainingImages);
      if (!mounted) return;
      cubit.addImages(pick.images, rejected: pick.rejected);
    } on PostImagePermissionDenied catch (denied) {
      if (mounted) _permissionDenied(camera: denied.camera);
    } catch (_) {
      if (mounted) {
        _snack(
          camera ? 'Unable to open the camera.' : 'Unable to open your photos.',
        );
      }
    } finally {
      _picking = false;
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _permissionDenied({required bool camera}) async {
    final open = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1F1F1F),
        title: Text(
          camera ? 'Camera access is off' : 'Photo access is off',
          style: createPostTextStyle.copyWith(
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Text(
          camera
              ? 'Allow camera access in Settings to take photos for your post.'
              : 'Allow photo access in Settings to add photos to your post.',
          style: createPostTextStyle.copyWith(
            fontSize: 14,
            color: Colors.white70,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Not now', style: createPostTextStyle),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'Open Settings',
              style: createPostTextStyle.copyWith(
                color: DarkColors.primaryColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
    if (open == true) await Geolocator.openAppSettings();
  }

  void _toggleEmoji() {
    setState(() => _showEmoji = !_showEmoji);
    if (_showEmoji) {
      FocusScope.of(context).unfocus();
    } else {
      _focus.requestFocus();
    }
  }

  void _insertEmoji(String emoji) {
    _text.value = insertChatEmoji(_text.value, emoji);
  }

  Future<void> _close() async {
    if (_allowPop || _confirmingClose) return;
    _confirmingClose = true;
    final discard = !_hasUnsavedContent || await showDiscardPostDialog(context);
    if (!mounted) return;
    if (!discard) {
      setState(() => _confirmingClose = false);
      return;
    }
    setState(() => _allowPop = true);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.pop(context);
  }

  Widget _header(CreatePostState state, CreatePostCubit cubit) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
    child: SizedBox(
      height: 44,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 84),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                'Create Post',
                style: createPostTextStyle.copyWith(
                  fontSize: 18,
                  height: 24 / 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                onPressed: _close,
                tooltip: 'Close composer',
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0x801F1F1F),
                  side: const BorderSide(color: Color(0x66595959)),
                  fixedSize: const Size(44, 44),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                icon: const Icon(Icons.close, size: 28, color: Colors.white),
              ),
              SizedBox(
                width: 80,
                height: 44,
                child: FilledButton(
                  key: const ValueKey('post-submit'),
                  onPressed: state.canSubmit && !_confirmingClose
                      ? _publish
                      : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: createPostAccent,
                    disabledBackgroundColor: createPostAccent.withValues(
                      alpha: 0.35,
                    ),
                    padding: EdgeInsets.zero,
                    shape: const StadiumBorder(),
                  ),
                  child: Text(
                    'Post',
                    style: createPostTextStyle.copyWith(
                      fontSize: 18,
                      height: 24 / 18,
                      fontWeight: FontWeight.w500,
                      color: state.canSubmit
                          ? DarkColors.whiteColor
                          : DarkColors.whiteColor.withValues(alpha: 0.5),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(
    BuildContext context,
  ) => BlocConsumer<CreatePostCubit, CreatePostState>(
    listenWhen: (previous, current) => previous.noticeId != current.noticeId,
    listener: (context, state) {
      if (state.notice != null) _snack(state.notice!);
    },
    builder: (context, state) {
      final cubit = context.read<CreatePostCubit>();
      final count = state.request.characterCount;
      final tooLong = count > CreatePostRequest.maxContentLength;
      return PopScope(
        canPop: _allowPop || (_text.text.isEmpty && !state.hasUnsavedContent),
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _close();
        },
        child: Scaffold(
          backgroundColor: createPostSurface,
          body: SafeArea(
            child: Column(
              children: [
                _header(state, cubit),
                Expanded(
                  child: SingleChildScrollView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            // Identity loads in the background; the
                            // fallback avatar and "You" stay dimmed until then.
                            AnimatedOpacity(
                              key: const ValueKey('post-author-avatar'),
                              opacity: state.loadingAuthor ? .5 : 1,
                              duration: const Duration(milliseconds: 200),
                              child: _AuthorAvatar(author: state.author),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: AnimatedOpacity(
                                key: const ValueKey('post-author-identity'),
                                opacity: state.loadingAuthor ? .5 : 1,
                                duration: const Duration(milliseconds: 200),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      state.author?.name ?? 'You',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: createPostTextStyle.copyWith(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    if (state.author?.username?.isNotEmpty ==
                                        true)
                                      Text(
                                        '@${state.author!.username}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: createPostTextStyle.copyWith(
                                          fontSize: 12,
                                          height: 16 / 12,
                                          color: DarkColors.greyColor,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            TextButton.icon(
                              onPressed: () async {
                                FocusScope.of(context).unfocus();
                                final visibility = await showAudienceSheet(
                                  context,
                                  state.visibility,
                                );
                                if (mounted && visibility != null) {
                                  cubit.setVisibility(visibility);
                                }
                              },
                              style: TextButton.styleFrom(
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                minimumSize: const Size(0, 36),
                                backgroundColor: createPostChip,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                shape: const StadiumBorder(),
                              ),
                              icon: state.visibility == PostVisibility.public
                                  ? SvgPicture.asset(
                                      'assets/images/icons/global.svg',
                                      width: 20,
                                      height: 20,
                                      colorFilter: const ColorFilter.mode(
                                        Colors.white,
                                        BlendMode.srcIn,
                                      ),
                                    )
                                  : Icon(
                                      audienceIcon(state.visibility),
                                      color: Colors.white,
                                      size: 20,
                                    ),
                              label: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    state.visibility.label,
                                    style: createPostTextStyle.copyWith(
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  // Iconsax arrow-left turned to point down.
                                  RotatedBox(
                                    quarterTurns: 3,
                                    child: SvgPicture.asset(
                                      'assets/images/home/arrow-left.svg',
                                      width: 20,
                                      height: 20,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        if (state.authorError != null)
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  state.authorError!,
                                  style: createPostTextStyle.copyWith(
                                    fontSize: 12,
                                    color: DarkColors.greyColor,
                                  ),
                                ),
                              ),
                              TextButton(
                                onPressed: cubit.loadAuthor,
                                child: Text(
                                  'Retry profile',
                                  style: createPostTextStyle.copyWith(
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        const SizedBox(height: 16),
                        TextField(
                          key: const ValueKey('post-content'),
                          controller: _text,
                          focusNode: _focus,
                          autofocus: true,
                          onTap: () {
                            if (_showEmoji) {
                              setState(() => _showEmoji = false);
                            }
                          },
                          minLines: 2,
                          maxLines: null,
                          keyboardType: TextInputType.multiline,
                          textCapitalization: TextCapitalization.sentences,
                          style: createPostTextStyle,
                          cursorColor: DarkColors.primaryColor,
                          decoration: InputDecoration(
                            hintText: 'What’s on your mind?',
                            hintStyle: createPostTextStyle.copyWith(
                              color: DarkColors.greyColor,
                            ),
                            filled: false,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            disabledBorder: InputBorder.none,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            '$count/${CreatePostRequest.maxContentLength}',
                            key: const ValueKey('post-character-count'),
                            style: createPostTextStyle.copyWith(
                              fontSize: 12,
                              height: 16 / 12,
                              color: tooLong
                                  ? Colors.redAccent
                                  : DarkColors.greyColor,
                            ),
                          ),
                        ),
                        if (tooLong)
                          Text(
                            'Posts must be ${CreatePostRequest.maxContentLength} characters or fewer.',
                            style: createPostTextStyle.copyWith(
                              fontSize: 14,
                              color: Colors.redAccent,
                            ),
                          ),
                        // Figma: photos sit between the counter and the
                        // "Add to your post" section.
                        if (state.images.isNotEmpty) ...[
                          const SizedBox(height: 28),
                          _ImageGrid(
                            images: state.images,
                            onRemove: cubit.removeImage,
                          ),
                          const SizedBox(height: 28),
                        ] else
                          const SizedBox(height: 24),
                        _AddToPost(
                          onGallery: () => _addImages(camera: false),
                          onCamera: () => _addImages(camera: true),
                          onEmoji: _toggleEmoji,
                          emojiOpen: _showEmoji,
                        ),
                      ],
                    ),
                  ),
                ),
                if (_showEmoji)
                  ChatEmojiPicker(onSelected: _insertEmoji, height: 260),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _AuthorAvatar extends StatelessWidget {
  const _AuthorAvatar({this.author});
  final PostAuthorModel? author;
  @override
  Widget build(BuildContext context) {
    const fallback = ColoredBox(
      color: DarkColors.darkgreyColor,
      child: Icon(Icons.person_outline, color: DarkColors.greyColor, size: 24),
    );
    final url = author?.avatarUrl;
    return ClipOval(
      child: SizedBox.square(
        dimension: 40,
        child: url == null || url.isEmpty
            ? fallback
            : Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => fallback,
              ),
      ),
    );
  }
}

class _AddToPost extends StatelessWidget {
  const _AddToPost({
    required this.onGallery,
    required this.onCamera,
    required this.onEmoji,
    required this.emojiOpen,
  });
  final VoidCallback onGallery, onCamera, onEmoji;
  final bool emojiOpen;

  // 24px icons in 44px tap targets, 8px apart (52px between icon centers).
  Widget _action({
    required String key,
    required String tooltip,
    required VoidCallback onPressed,
    required Widget icon,
  }) => IconButton(
    key: ValueKey(key),
    tooltip: tooltip,
    onPressed: onPressed,
    style: IconButton.styleFrom(
      fixedSize: const Size(44, 44),
      minimumSize: const Size(44, 44),
      padding: EdgeInsets.zero,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    ),
    icon: icon,
  );

  // The icon SVGs are already filled with the Figma grey.
  Widget _svg(String path, {Color? tint}) => SvgPicture.asset(
    path,
    width: 24,
    height: 24,
    colorFilter: tint == null ? null : ColorFilter.mode(tint, BlendMode.srcIn),
  );

  @override
  Widget build(BuildContext context) => Column(
    key: const ValueKey('add-to-post'),
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Add to your post',
        style: createPostTextStyle.copyWith(
          fontSize: 14,
          height: 20 / 14,
          color: DarkColors.greyColor,
        ),
      ),
      const SizedBox(height: 8),
      Row(
        spacing: 8,
        children: [
          _action(
            key: 'add-gallery',
            tooltip: 'Add photos',
            onPressed: onGallery,
            icon: _svg('assets/images/icons/gallery-add.svg'),
          ),
          _action(
            key: 'add-camera',
            tooltip: 'Take a photo',
            onPressed: onCamera,
            icon: _svg('assets/images/icons/camera.svg'),
          ),
          _action(
            key: 'add-emoji',
            tooltip: emojiOpen ? 'Show keyboard' : 'Add emoji',
            onPressed: onEmoji,
            icon: _svg(
              'assets/images/interactions/happyemoji.svg',
              tint: emojiOpen ? createPostAccent : createPostIconGrey,
            ),
          ),
        ],
      ),
    ],
  );
}

class _ImageGrid extends StatelessWidget {
  const _ImageGrid({required this.images, required this.onRemove});
  final List<PostImage> images;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) => GridView.builder(
    key: const ValueKey('post-image-grid'),
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    padding: EdgeInsets.zero,
    itemCount: images.length,
    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: 3,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
    ),
    itemBuilder: (context, index) {
      final image = images[index];
      return Stack(
        key: ValueKey('post-image-${image.localId}'),
        fit: StackFit.expand,
        children: [
          // Figma tiles have square corners.
          Image.memory(
            image.bytes,
            fit: BoxFit.cover,
            cacheWidth: 360,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) =>
                const ColoredBox(color: DarkColors.darkgreyColor),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: Material(
              color: createPostChip,
              shape: const CircleBorder(),
              child: InkWell(
                key: ValueKey('remove-image-${image.localId}'),
                customBorder: const CircleBorder(),
                onTap: () => onRemove(image.localId),
                child: const SizedBox.square(
                  dimension: 32,
                  child: Icon(
                    Icons.close,
                    size: 24,
                    color: Colors.white,
                    semanticLabel: 'Remove photo',
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
}
