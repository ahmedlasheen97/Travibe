import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:travibe/features/create_post/cubit/post_upload_cubit.dart';
import 'package:travibe/features/create_post/widgets/create_post_styles.dart';
import 'package:travibe/features/create_post/widgets/discard_post_dialog.dart';

/// Bottom toast for the background post upload: progress while uploading,
/// Retry/Discard after a failure. Hidden otherwise.
class PostUploadToast extends StatelessWidget {
  const PostUploadToast({super.key});

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<PostUploadCubit, PostUploadState>(
        builder: (context, state) {
          final child = switch (state) {
            PostUploading() => const _Toast(
              key: ValueKey('post-upload-progress'),
              title: 'Uploading your post',
              leading: SizedBox.square(
                dimension: 20,
                child: CupertinoActivityIndicator(
                  radius: 10,
                  color: DarkColors.whiteColor,
                ),
              ),
            ),
            PostUploadFailed(:final message) => _Toast(
              key: const ValueKey('post-upload-failed'),
              title: 'Couldn’t upload your post',
              subtitle: message,
              actions: [
                TextButton(
                  onPressed: () async {
                    final cubit = context.read<PostUploadCubit>();
                    if (await showDiscardPostDialog(context)) cubit.discard();
                  },
                  child: Text(
                    'Discard',
                    style: createPostTextStyle.copyWith(
                      fontSize: 14,
                      color: createPostDanger,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: context.read<PostUploadCubit>().retry,
                  child: Text(
                    'Retry',
                    style: createPostTextStyle.copyWith(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: createPostAccent,
                    ),
                  ),
                ),
              ],
            ),
            _ => const SizedBox.shrink(),
          };
          return AnimatedSwitcher(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 200),
            child: child,
          );
        },
      );
}

/// Figma: 350 wide (20px side margins), ~46 tall, radius 8, #2D2C2B at 90%.
class _Toast extends StatelessWidget {
  const _Toast({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.actions = const [],
  });
  final String title;
  final String? subtitle;
  final Widget? leading;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    container: true,
    child: Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      constraints: const BoxConstraints(minHeight: 46),
      padding: EdgeInsets.fromLTRB(12, 0, actions.isEmpty ? 12 : 4, 0),
      decoration: BoxDecoration(
        color: createPostToast,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 10)],
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 11),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: createPostTextStyle),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      maxLines: 2,
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
          ...actions,
        ],
      ),
    ),
  );
}
