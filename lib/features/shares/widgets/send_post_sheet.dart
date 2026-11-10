import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:travibe/core/widgets/sheet_handle.dart';
import 'package:travibe/features/home/widgets/home_user_avatar.dart';
import 'package:travibe/features/shares/cubit/send_post_cubit.dart';
import 'package:travibe/features/shares/data/post_share_actions.dart';
import 'package:travibe/features/shares/data/send_post_repo.dart';

const _text = TextStyle(
  fontFamily: 'Plus Jakarta Sans',
  fontSize: 14,
  color: DarkColors.whiteColor,
  decoration: TextDecoration.none,
  height: 1.5,
);

class SendPostSheet extends StatefulWidget {
  const SendPostSheet({
    super.key,
    required this.postText,
    this.repo,
    this.actions,
  });
  final String postText;
  final SendPostRepo? repo;
  final PostShareActions? actions;

  static Future<void> show(
    BuildContext context, {
    required String postText,
    SendPostRepo? repo,
    PostShareActions? actions,
  }) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: DarkColors.backgroundColor,
    clipBehavior: Clip.antiAlias,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) =>
        SendPostSheet(postText: postText, repo: repo, actions: actions),
  );

  @override
  State<SendPostSheet> createState() => _SendPostSheetState();
}

class _SendPostSheetState extends State<SendPostSheet> {
  late final SendPostCubit _people;
  late final PostShareActions _actions;
  bool _busy = false;
  String? _feedback;

  @override
  void initState() {
    super.initState();
    _actions = widget.actions ?? PostShareActions(text: widget.postText);
    _people = SendPostCubit(repo: widget.repo)..load();
  }

  @override
  void dispose() {
    _people.close();
    super.dispose();
  }

  Future<void> _external({
    required bool copy,
    required BuildContext anchor,
  }) async {
    if (_busy || (copy ? !_actions.available : !_actions.canShare)) return;
    setState(() {
      _busy = true;
      _feedback = null;
    });
    try {
      if (copy) {
        await _actions.copyLink();
      } else {
        final box = anchor.findRenderObject() as RenderBox;
        final origin = box.localToGlobal(Offset.zero) & box.size;
        await _actions.moreOptions(origin);
      }
      if (mounted && copy) setState(() => _feedback = 'Link copied');
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint(
          'SendPostSheet ${copy ? 'Copy Link' : 'More Options'} failed '
          'on ${defaultTargetPlatform.name}; '
          'operation=${copy ? 'Clipboard.setData' : 'travibe/post_sharing.share'}: $error',
        );
        debugPrintStack(stackTrace: stackTrace);
      }
      if (mounted) {
        setState(
          () => _feedback = copy
              ? 'Unable to copy the link. Please try again.'
              : 'Unable to open sharing options. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SheetHandle(),
            const SizedBox(height: 20),
            Text(
              'Send Post',
              style: _text.copyWith(fontSize: 20, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 20),
            TextField(
              key: const ValueKey('send-post-search'),
              onChanged: _people.search,
              style: _text,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search people',
                hintStyle: _text.copyWith(color: DarkColors.greyColor),
                prefixIcon: const Icon(
                  Icons.search,
                  color: DarkColors.greyColor,
                ),
                filled: true,
                fillColor: DarkColors.darkgreyColor,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 20),
            BlocBuilder<SendPostCubit, SendPostState>(
              bloc: _people,
              builder: (context, state) => Column(
                children: [
                  if (!state.validQuery)
                    Text('Search must contain 3–100 characters.', style: _text)
                  else if (state.loading)
                    const SizedBox(
                      height: 96,
                      child: Center(
                        child: CircularProgressIndicator(
                          semanticsLabel: 'Loading people',
                        ),
                      ),
                    )
                  else ...[
                    if (state.users.isNotEmpty)
                      SizedBox(
                        height: 100,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount:
                              state.users.length + (state.hasMore ? 1 : 0),
                          separatorBuilder: (_, _) => const SizedBox(width: 12),
                          itemBuilder: (context, index) {
                            if (index == state.users.length) {
                              return Center(
                                child: TextButton(
                                  onPressed: state.loadingMore
                                      ? null
                                      : _people.more,
                                  child: Text(
                                    state.loadingMore
                                        ? 'Loading…'
                                        : 'More people',
                                    style: _text,
                                  ),
                                ),
                              );
                            }
                            final user = state.users[index];
                            return SizedBox(
                              width: 68,
                              child: Column(
                                children: [
                                  HomeUserAvatar(url: user.avatarUrl),
                                  const SizedBox(height: 8),
                                  Text(
                                    user.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: _text.copyWith(fontSize: 12),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      )
                    else if (state.error == null)
                      Text(
                        state.query.isEmpty
                            ? 'No suggested people yet.'
                            : 'No people found.',
                        style: _text,
                      ),
                    if (state.error != null) ...[
                      Text(
                        state.error!,
                        style: _text,
                        textAlign: TextAlign.center,
                      ),
                      TextButton(
                        onPressed: state.loadingMore
                            ? null
                            : state.hasMore
                            ? _people.more
                            : _people.load,
                        child: Text('Retry people', style: _text),
                      ),
                    ],
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Divider(color: DarkColors.darkgreyColor, height: 1),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Builder(
                    builder: (anchor) => _action(
                      'Copy Link',
                      SvgPicture.asset(
                        'assets/images/interactions/link.svg',
                        width: 46,
                        height: 46,
                      ),
                      _busy || !_actions.available
                          ? null
                          : () => _external(copy: true, anchor: anchor),
                    ),
                  ),
                ),
                Expanded(
                  child: Builder(
                    builder: (anchor) => _action(
                      'More Options',
                      SvgPicture.asset(
                        'assets/images/interactions/share.svg',
                        width: 32,
                        height: 32,
                      ),
                      _busy || !_actions.canShare
                          ? null
                          : () => _external(copy: false, anchor: anchor),
                    ),
                  ),
                ),
              ],
            ),
            if (!_actions.available) ...[
              const SizedBox(height: 8),
              Text(
                _actions.canShare
                    ? 'Shares text only; no link to the original post.'
                    : 'A public post link is not available yet.',
                textAlign: TextAlign.center,
                style: _text.copyWith(
                  fontSize: 12,
                  color: DarkColors.greyColor,
                ),
              ),
            ],
            if (_feedback != null) ...[
              const SizedBox(height: 8),
              Semantics(
                liveRegion: true,
                child: Text(
                  _feedback!,
                  style: _text,
                  textAlign: TextAlign.center,
                ),
              ),
            ],
            if (_busy)
              const LinearProgressIndicator(
                semanticsLabel: 'Opening share action',
              ),
          ],
        ),
      ),
    ),
  );

  Widget _action(String label, Widget icon, VoidCallback? onPressed) =>
      TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: DarkColors.whiteColor,
          disabledForegroundColor: DarkColors.greyColor,
        ),
        child: Column(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: const BoxDecoration(
                color: DarkColors.darkgreyColor,
                shape: BoxShape.circle,
              ),
              child: Center(child: icon),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: _text.copyWith(
                color: onPressed == null
                    ? DarkColors.greyColor
                    : DarkColors.whiteColor,
              ),
            ),
          ],
        ),
      );
}
