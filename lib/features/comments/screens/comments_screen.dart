import 'package:travibe/features/chats/screens/chat_navigation.dart';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/utils/formatters.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:travibe/features/comments/widgets/comment_row.dart';
import 'package:travibe/core/widgets/error_retry_view.dart';
import 'package:travibe/features/comments/cubit/comments_cubit.dart';
import 'package:travibe/features/comments/data/comment_model.dart';
import 'package:travibe/features/comments/data/comments_repo.dart';
import 'package:travibe/features/likes/cubit/likes_cubit.dart';

class CommentsScreen extends StatelessWidget {
  const CommentsScreen({
    super.key,
    this.parentId,
    this.commentsDisabled = false,
  });
  final int? parentId;
  final bool commentsDisabled;

  static Future<void> open(
    BuildContext context, {
    required int postId,
    int initialCount = 0,
    bool commentsDisabled = false,
    int? parentId,
    CommentsRepo? repo,
    LikesCubit? likes,
    void Function(int)? onCountChanged,
    void Function(ApiError)? onSyncError,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (sheetContext) => chatRouteScope(
        context,
        BlocProvider(
          create: (_) => CommentsCubit(
            postId: postId,
            initialCount: initialCount,
            repo: repo,
            likes: likes,
            onCountChanged: onCountChanged,
            onSyncError: onSyncError,
          )..load(parentId: parentId),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final keyboard = MediaQuery.viewInsetsOf(context).bottom;
              return AnimatedPadding(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                padding: EdgeInsets.only(bottom: keyboard),
                child: SizedBox(
                  height: math.min(
                    614,
                    math.max(0, constraints.maxHeight - keyboard),
                  ),
                  child: CommentsScreen(
                    parentId: parentId,
                    commentsDisabled: commentsDisabled,
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) =>
      _CommentsView(parentId: parentId, commentsDisabled: commentsDisabled);
}

class _CommentsView extends StatefulWidget {
  const _CommentsView({this.parentId, required this.commentsDisabled});
  final int? parentId;
  final bool commentsDisabled;
  @override
  State<_CommentsView> createState() => _CommentsViewState();
}

class _CommentsViewState extends State<_CommentsView> {
  final _text = TextEditingController();
  CommentModel? _editing;
  CommentModel? _replying;
  String? _mutationError;
  final _focus = FocusNode();
  final Set<int> _expanded = {};

  int? get _parentId => _replying?.id ?? widget.parentId;

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final cubit = context.read<CommentsCubit>();
    final result = _editing == null
        ? await cubit.create(_text.text, parentId: _parentId)
        : await cubit.edit(_editing!, _text.text);
    if (!mounted) return;
    if (result.error != null) _error(result.error!);
    if (result.confirmed) {
      setState(() {
        _text.clear();
        _editing = null;
        _mutationError = null;
      });
    }
  }

  void _error(ApiError error) => setState(() => _mutationError = error.message);

  Future<void> _like(CommentModel comment) async {
    final error = await context.read<CommentsCubit>().toggleLike(comment);
    if (error != null && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _delete(CommentModel comment) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Delete comment?'),
        content: const Text(
          'Replies may also be affected. Deleted replies are restored individually.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final cubit = context.read<CommentsCubit>();
    final result = await cubit.delete(comment);
    if (!mounted) return;
    if (result.error != null) _error(result.error!);
    if (result.confirmed) {
      if (_editing?.id == comment.id) {
        setState(() {
          _editing = null;
          _text.clear();
        });
      }
      // Restore controls remain in the sheet, above any keyboard or modal barrier.
      if (_replying?.id == comment.id) {
        setState(() {
          _replying = null;
          _text.clear();
        });
      }
    }
  }

  Future<void> _restore(int id, {CommentsCubit? cubit}) async {
    if (cubit == null && !mounted) return;
    final result = await (cubit ?? context.read<CommentsCubit>()).restore(id);
    if (mounted && result.error != null) _error(result.error!);
  }

  void _expand(CommentModel comment, {bool reply = false}) {
    final cubit = context.read<CommentsCubit>();
    cubit.remember(comment);
    setState(() {
      if (reply || !_expanded.contains(comment.id)) {
        _expanded.add(comment.id);
      } else {
        _expanded.remove(comment.id);
      }
      if (reply) {
        _replying = comment;
        _editing = null;
        _mutationError = null;
      }
    });
    if (_expanded.contains(comment.id) &&
        cubit.state.thread(comment.id).status == CommentsStatus.initial) {
      cubit.load(parentId: comment.id);
    }
    if (reply) _focus.requestFocus();
  }

  void _edit(CommentModel comment) {
    setState(() {
      _editing = comment;
      _replying = null;
      _mutationError = null;
      _text.text = comment.content ?? '';
    });
    _focus.requestFocus();
  }

  Widget _restoreControls(CommentsState state, int? parentId) => Wrap(
    children: [
      for (final comment in state.deleted.values.where(
        (c) => c.parentId == parentId,
      ))
        TextButton(
          onPressed: state.busy ? null : () => _restore(comment.id),
          child: Text(
            'Restore: ${comment.content ?? 'comment'}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: commentTextStyle.copyWith(color: DarkColors.greyColor),
          ),
        ),
    ],
  );

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<CommentsCubit, CommentsState>(
        builder: (context, state) {
          final cubit = context.read<CommentsCubit>();
          return Material(
            color: const Color(0xFF0A0A0A),
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              side: BorderSide(color: Color(0x66595959)),
            ),
            clipBehavior: Clip.antiAlias,
            child: DefaultTextStyle(
              style: commentTextStyle,
              child: SafeArea(
                top: false,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 16, bottom: 32),
                      child: Container(
                        width: 112,
                        height: 4,
                        decoration: BoxDecoration(
                          color: DarkColors.whiteColor,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        children: [
                          Text(
                            widget.parentId == null ? 'Comments' : 'Replies',
                            style: commentTextStyle.copyWith(
                              fontSize: 18,
                              height: 24 / 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            formatCount(state.count),
                            key: const ValueKey('comment-count'),
                            style: commentTextStyle.copyWith(
                              color: DarkColors.greyColor,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    if (state.syncError != null)
                      _message(
                        'Count refresh failed: ${state.syncError!.message}',
                        onRetry: state.busy || state.syncing
                            ? null
                            : cubit.synchronize,
                      ),
                    if (state.syncing)
                      const LinearProgressIndicator(minHeight: 2),
                    Expanded(child: _thread(state)),
                    if (_mutationError != null)
                      _message(
                        _mutationError!,
                        onDismiss: () => setState(() => _mutationError = null),
                      ),
                    _composer(state),
                  ],
                ),
              ),
            ),
          );
        },
      );

  Widget _message(
    String message, {
    VoidCallback? onRetry,
    VoidCallback? onDismiss,
  }) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20),
    child: Row(
      children: [
        Expanded(
          child: Text(
            message,
            style: commentTextStyle.copyWith(color: DarkColors.greyColor),
          ),
        ),
        if (onRetry != null)
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        if (onDismiss != null)
          IconButton(
            onPressed: onDismiss,
            tooltip: 'Dismiss error',
            icon: const Icon(Icons.close, size: 20, color: commentMutedColor),
          ),
      ],
    ),
  );

  Widget _composer(CommentsState state) {
    final unavailable =
        widget.commentsDisabled || state.deleted.containsKey(_parentId);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        MediaQuery.viewInsetsOf(context).bottom > 0
            ? 12
            : math.max(0, 34 - MediaQuery.paddingOf(context).bottom),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_editing != null || _replying != null)
            Row(
              children: [
                Expanded(
                  child: Text(
                    _editing != null
                        ? 'Editing comment'
                        : 'Replying to ${_replying!.user?.name ?? 'User'}',
                    style: commentTextStyle.copyWith(
                      color: DarkColors.greyColor,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: state.busy
                      ? null
                      : () => setState(() {
                          _editing = null;
                          _replying = null;
                          _text.clear();
                          _mutationError = null;
                        }),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          if (unavailable && _editing == null)
            const Text('New comments are unavailable.', style: commentTextStyle)
          else
            ClipRRect(
              borderRadius: BorderRadius.circular(50),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 48),
                  decoration: BoxDecoration(
                    color: const Color(0x801F1F1F),
                    border: Border.all(color: const Color(0x66595959)),
                    borderRadius: BorderRadius.circular(50),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.sentiment_satisfied_alt,
                        size: 20,
                        color: DarkColors.whiteColor,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _text,
                          focusNode: _focus,
                          enabled: !state.busy,
                          minLines: 1,
                          maxLines: 4,
                          style: commentTextStyle.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                          cursorColor: DarkColors.whiteColor,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: InputDecoration(
                            hintText: _editing != null
                                ? 'Edit comment'
                                : _parentId == null
                                ? 'Add a comment'
                                : 'Add a reply',
                            hintStyle: commentTextStyle.copyWith(
                              color: DarkColors.greyColor,
                              fontWeight: FontWeight.w500,
                            ),
                            filled: false,
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 11,
                            ),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            disabledBorder: InputBorder.none,
                          ),
                        ),
                      ),
                      ValueListenableBuilder<TextEditingValue>(
                        valueListenable: _text,
                        builder: (context, value, _) =>
                            value.text.trim().isEmpty && !state.busy
                            ? const SizedBox.shrink()
                            : SizedBox(
                                width: 40,
                                height: 40,
                                child: IconButton(
                                  padding: EdgeInsets.zero,
                                  onPressed: state.busy ? null : _submit,
                                  tooltip: _editing == null ? 'Send' : 'Save',
                                  icon: state.busy
                                      ? const SizedBox.square(
                                          dimension: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : Icon(
                                          _editing == null
                                              ? Icons.send_outlined
                                              : Icons.check,
                                          size: 20,
                                          color: DarkColors.whiteColor,
                                        ),
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _thread(CommentsState state) {
    final cubit = context.read<CommentsCubit>();
    final thread = state.thread(widget.parentId);
    if (thread.status == CommentsStatus.initial ||
        thread.status == CommentsStatus.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (thread.status == CommentsStatus.failure) {
      return ErrorRetryView(
        message: thread.error!.message,
        onRetry: () => cubit.load(parentId: widget.parentId),
      );
    }
    return RefreshIndicator(
      onRefresh: () async {
        await Future.wait([
          cubit.load(parentId: widget.parentId),
          for (final id in _expanded) cubit.load(parentId: id),
        ]);
      },
      child: NotificationListener<ScrollNotification>(
        onNotification: (event) {
          if (event.depth == 0 && event.metrics.extentAfter < 300) {
            cubit.more(parentId: widget.parentId);
          }
          return false;
        },
        child: CustomScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              sliver: SliverList.list(
                children: [
                  if (widget.parentId != null &&
                      state.known[widget.parentId] != null)
                    Text(
                      state.deleted.containsKey(widget.parentId)
                          ? 'This comment was deleted.'
                          : state.known[widget.parentId]!.content ??
                                'Media comment',
                      style: commentTextStyle,
                    ),
                  if (thread.refreshing)
                    const LinearProgressIndicator(minHeight: 2),
                  if (thread.error != null)
                    ErrorRetryView(
                      message: thread.error!.message,
                      onRetry: () => cubit.load(parentId: widget.parentId),
                    ),
                  if (thread.comments.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: Text('No comments yet')),
                    ),
                  _restoreControls(state, widget.parentId),
                ],
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              sliver: SliverList.builder(
                itemCount: thread.comments.length,
                itemBuilder: (context, index) =>
                    _comment(thread.comments[index], state, 0),
              ),
            ),
            SliverToBoxAdapter(child: _pagination(thread, widget.parentId)),
          ],
        ),
      ),
    );
  }

  Widget _comment(CommentModel comment, CommentsState state, int depth) =>
      Padding(
        key: ValueKey('comment-${comment.id}'),
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CommentRow(
              comment: comment,
              busy:
                  state.busy ||
                  context.read<CommentsCubit>().isLikePending(comment.id),
              likePending: context.read<CommentsCubit>().isLikePending(
                comment.id,
              ),
              onLike: () => _like(comment),
              expanded: _expanded.contains(comment.id),
              onReply: widget.commentsDisabled || state.busy
                  ? null
                  : () => _expand(comment, reply: true),
              onToggleReplies: () => _expand(comment),
              onEdit: () => _edit(comment),
              onDelete: () => _delete(comment),
            ),
            if (_expanded.contains(comment.id))
              Padding(
                padding: EdgeInsets.only(left: depth < 2 ? 40 : 0, top: 12),
                child: _replies(comment.id, state, depth + 1),
              ),
          ],
        ),
      );

  Widget _replies(int parentId, CommentsState state, int depth) {
    final thread = state.thread(parentId);
    final cubit = context.read<CommentsCubit>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (thread.status == CommentsStatus.initial ||
            thread.status == CommentsStatus.loading)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (thread.status == CommentsStatus.failure)
          ErrorRetryView(
            message: thread.error!.message,
            onRetry: () => cubit.load(parentId: parentId),
          )
        else ...[
          if (thread.refreshing) const LinearProgressIndicator(minHeight: 2),
          if (thread.error != null)
            ErrorRetryView(
              message: thread.error!.message,
              onRetry: () => cubit.load(parentId: parentId),
            ),
          if (thread.comments.isEmpty)
            const Text('No replies yet', style: commentTextStyle),
          for (final comment in thread.comments)
            _comment(comment, state, depth),
          _pagination(thread, parentId),
        ],
        _restoreControls(state, parentId),
      ],
    );
  }

  Widget _pagination(CommentThreadState thread, int? parentId) {
    final cubit = context.read<CommentsCubit>();
    if (thread.loadingMore) {
      return const Center(child: CircularProgressIndicator());
    }
    if (thread.paginationError != null) {
      return ErrorRetryView(
        message: thread.paginationError!.message,
        onRetry: () => cubit.more(parentId: parentId, retry: true),
      );
    }
    return thread.hasMore
        ? TextButton(
            onPressed: () => cubit.more(parentId: parentId),
            child: Text(parentId == null ? 'Load more' : 'Load more replies'),
          )
        : const SizedBox.shrink();
  }
}
