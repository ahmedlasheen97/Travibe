import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:travibe/features/create_post/cubit/create_post_cubit.dart';
import 'package:travibe/features/create_post/data/create_post_repo.dart';
import 'package:travibe/features/create_post/data/create_post_request.dart';
import 'package:travibe/features/create_post/widgets/audience_sheet.dart';
import 'package:travibe/features/create_post/widgets/create_post_styles.dart';
import 'package:travibe/features/create_post/widgets/discard_post_dialog.dart';
import 'package:travibe/features/home/data/post_model.dart';

class CreatePostScreen extends StatelessWidget {
  const CreatePostScreen({super.key, this.repo});
  final CreatePostRepo? repo;

  static Future<PostModel?> open(
    BuildContext context, {
    CreatePostRepo? repo,
  }) => Navigator.of(context).push<PostModel>(
    MaterialPageRoute(builder: (_) => CreatePostScreen(repo: repo)),
  );

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => CreatePostCubit(repo: repo)..loadAuthor(),
    child: const _Composer(),
  );
}

class _Composer extends StatefulWidget {
  const _Composer();
  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer> {
  final _text = TextEditingController();
  bool _allowPop = false;
  bool _confirmingClose = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _close() async {
    final cubit = context.read<CreatePostCubit>();
    if (cubit.state.isSubmitting ||
        cubit.state.status == CreatePostStatus.success ||
        _confirmingClose) {
      return;
    }
    _confirmingClose = true;
    final discard = _text.text.isEmpty || await showDiscardPostDialog(context);
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
                onPressed: state.isSubmitting ? null : _close,
                tooltip: 'Close composer',
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0x801F1F1F),
                  side: const BorderSide(color: Color(0x66595959)),
                  fixedSize: const Size(44, 44),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                icon: const Icon(Icons.close, size: 24, color: Colors.white),
              ),
              SizedBox(
                width: 80,
                height: 44,
                child: FilledButton(
                  onPressed: state.canSubmit && !_confirmingClose
                      ? cubit.submit
                      : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: DarkColors.primaryColor,
                    disabledBackgroundColor: DarkColors.primaryColor.withValues(
                      alpha: 0.35,
                    ),
                    padding: EdgeInsets.zero,
                    shape: const StadiumBorder(),
                  ),
                  child: state.isSubmitting
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          'Post',
                          style: createPostTextStyle.copyWith(
                            fontSize: 18,
                            height: 24 / 18,
                            fontWeight: FontWeight.w500,
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
    listenWhen: (previous, current) => previous.status != current.status,
    listener: (context, state) {
      if (state.status == CreatePostStatus.success) {
        setState(() => _allowPop = true);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.pop(context, state.post);
        });
      }
    },
    builder: (context, state) {
      final cubit = context.read<CreatePostCubit>();
      final count = state.request.characterCount;
      final tooLong = count > CreatePostRequest.maxContentLength;
      return PopScope(
        canPop: _allowPop || (!state.isSubmitting && _text.text.isEmpty),
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
                            _AuthorAvatar(author: state.author),
                            const SizedBox(width: 8),
                            Expanded(
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
                            const SizedBox(width: 8),
                            TextButton.icon(
                              onPressed: state.isSubmitting
                                  ? null
                                  : () async {
                                      FocusScope.of(context).unfocus();
                                      final visibility =
                                          await showAudienceSheet(
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
                                backgroundColor: const Color(0xFF2F2E2D),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                shape: const StadiumBorder(),
                              ),
                              icon: Icon(
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
                                  const Icon(
                                    Icons.keyboard_arrow_down,
                                    size: 20,
                                    color: Colors.white,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        if (state.loadingAuthor)
                          const Padding(
                            padding: EdgeInsets.only(top: 8),
                            child: LinearProgressIndicator(minHeight: 2),
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
                          autofocus: true,
                          enabled: !state.isSubmitting,
                          minLines: 2,
                          maxLines: null,
                          keyboardType: TextInputType.multiline,
                          textCapitalization: TextCapitalization.sentences,
                          style: createPostTextStyle,
                          cursorColor: DarkColors.primaryColor,
                          onChanged: cubit.setContent,
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
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            '$count/2000',
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
                            'Posts must be 2000 characters or fewer.',
                            style: createPostTextStyle.copyWith(
                              fontSize: 14,
                              color: Colors.redAccent,
                            ),
                          ),
                        if (state.isSubmitting)
                          Padding(
                            padding: const EdgeInsets.only(top: 20),
                            child: Semantics(
                              liveRegion: true,
                              child: const Text(
                                'Publishing your post…',
                                style: createPostTextStyle,
                              ),
                            ),
                          ),
                        if (state.error != null)
                          Container(
                            margin: const EdgeInsets.only(top: 20),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.red.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Semantics(
                                    liveRegion: true,
                                    child: Text(
                                      state.error!.message,
                                      style: createPostTextStyle.copyWith(
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                ),
                                if (state.canSubmit)
                                  TextButton(
                                    onPressed: cubit.submit,
                                    child: Text(
                                      'Retry',
                                      style: createPostTextStyle.copyWith(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                              ],
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
