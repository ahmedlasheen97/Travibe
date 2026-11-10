import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/features/shares/cubit/shares_cubit.dart';
import 'package:travibe/features/shares/data/share_model.dart';

const _shareTextStyle = TextStyle(
  fontFamily: 'Plus Jakarta Sans',
  fontSize: 14,
  height: 1.5,
  decoration: TextDecoration.none,
);

/// Simple existing-app confirmation pattern until repost-specific Figma is available.
class SharePostDialog extends StatefulWidget {
  const SharePostDialog({
    super.key,
    required this.postId,
    required this.shares,
  });
  final int postId;
  final SharesCubit shares;
  static Future<ShareOutcome?> show(
    BuildContext context, {
    required int postId,
    required SharesCubit shares,
  }) => showDialog<ShareOutcome>(
    context: context,
    barrierDismissible: false,
    builder: (_) => SharePostDialog(postId: postId, shares: shares),
  );
  @override
  State<SharePostDialog> createState() => _SharePostDialogState();
}

class _SharePostDialogState extends State<SharePostDialog> {
  final _note = TextEditingController();
  @override
  void initState() {
    super.initState();
    widget.shares.inspect(widget.postId);
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _confirm(bool remove) async {
    final result = remove
        ? await widget.shares.delete(widget.postId)
        : await widget.shares.create(
            widget.postId,
            CreateShareRequest(comment: _note.text),
          );
    if (mounted && result.confirmed) Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) => BlocBuilder<SharesCubit, SharesState>(
    bloc: widget.shares,
    builder: (context, state) {
      final post = state.post(widget.postId);
      final remove = post.ownShare != null;
      final busy = post.pending || post.loading;
      return PopScope(
        canPop: !post.pending,
        child: AlertDialog(
          backgroundColor: const Color(0xFF141414),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: Text(
            remove ? 'Unshare post?' : 'Share post?',
            style: _shareTextStyle.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 20,
            ),
          ),
          scrollable: true,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (post.loading)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(
                    child: CircularProgressIndicator(
                      semanticsLabel: 'Checking share status',
                    ),
                  ),
                ),
              if (post.ownershipKnown && !post.loading) ...[
                Text(
                  remove
                      ? 'Remove your share? The original post will stay available.'
                      : 'Share this post to your profile.',
                  style: _shareTextStyle.copyWith(color: Colors.white70),
                ),
                if (!remove) ...[
                  const SizedBox(height: 16),
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _note,
                    builder: (context, value, _) => TextField(
                      controller: _note,
                      enabled: !busy,
                      minLines: 1,
                      maxLines: 3,
                      style: _shareTextStyle.copyWith(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'Add a note (optional)',
                        labelStyle: _shareTextStyle.copyWith(
                          color: Colors.white70,
                        ),
                        counterStyle: _shareTextStyle.copyWith(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                        errorStyle: _shareTextStyle.copyWith(
                          color: Colors.redAccent,
                          fontSize: 12,
                        ),
                        counterText: '${value.text.trim().runes.length}/500',
                        errorText: CreateShareRequest(
                          comment: value.text,
                        ).validationError,
                        filled: true,
                        fillColor: const Color(0xFF242424),
                      ),
                    ),
                  ),
                ],
              ],
              if (post.error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    post.error!.message,
                    style: _shareTextStyle.copyWith(color: Colors.redAccent),
                  ),
                ),
              if (post.syncError != null) ...[
                const SizedBox(height: 12),
                Text(
                  'Share updated. The count could not be refreshed.',
                  style: _shareTextStyle.copyWith(color: Colors.white70),
                ),
                TextButton(
                  onPressed: busy
                      ? null
                      : () => widget.shares.refreshCount(widget.postId),
                  child: const Text('Retry count', style: _shareTextStyle),
                ),
              ],
              if (post.pending)
                const Padding(
                  padding: EdgeInsets.only(top: 16),
                  child: LinearProgressIndicator(
                    semanticsLabel: 'Updating share',
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: post.pending
                  ? null
                  : () {
                      if (!widget.shares.post(widget.postId).pending) {
                        Navigator.pop(context);
                      }
                    },
              child: const Text('Cancel', style: _shareTextStyle),
            ),
            if (!post.ownershipKnown)
              TextButton(
                onPressed: busy
                    ? null
                    : () => widget.shares.inspect(widget.postId, force: true),
                child: const Text('Retry', style: _shareTextStyle),
              )
            else
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _note,
                builder: (context, value, _) => TextButton(
                  onPressed:
                      busy ||
                          (!remove &&
                              CreateShareRequest(
                                    comment: value.text,
                                  ).validationError !=
                                  null) ||
                          (remove && !widget.shares.canDelete(widget.postId))
                      ? null
                      : () => _confirm(remove),
                  child: Text(
                    post.pending
                        ? 'Please wait…'
                        : remove
                        ? 'Unshare'
                        : 'Share',
                    style: _shareTextStyle,
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );
}
