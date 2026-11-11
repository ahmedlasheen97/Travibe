import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:travibe/core/models/public_user_model.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:travibe/core/widgets/custom_button.dart';
import 'package:travibe/core/widgets/sheet_handle.dart';
import 'package:travibe/features/home/data/post_model.dart';
import 'package:travibe/features/home/widgets/home_user_avatar.dart';
import 'package:travibe/features/shares/cubit/send_post_cubit.dart';
import 'package:travibe/features/shares/data/post_share_actions.dart';
import 'package:travibe/features/shares/data/send_post_repo.dart';
import 'package:travibe/features/shares/data/share_post_messenger.dart';

const _text = TextStyle(
  fontFamily: 'Plus Jakarta Sans',
  fontSize: 14,
  color: DarkColors.whiteColor,
  decoration: TextDecoration.none,
  height: 1.5,
);
const _divider = Color(0xFF262626);
const _gutter = 20.0;

class SendPostSheet extends StatefulWidget {
  const SendPostSheet({
    super.key,
    required this.post,
    this.repo,
    this.messenger,
    this.actions,
  });
  final PostModel post;
  final SendPostRepo? repo;
  final SharePostMessenger? messenger;
  final PostShareActions? actions;

  static String fallbackText(PostModel post) =>
      post.content?.trim().isNotEmpty == true
      ? post.content!
      : 'A post on Travibe.';

  /// Only public posts can be sent; others show a SnackBar instead.
  static Future<void> show(
    BuildContext context, {
    required PostModel post,
    SendPostRepo? repo,
    SharePostMessenger? messenger,
    PostShareActions? actions,
  }) async {
    final id = int.tryParse(post.id);
    if (id == null || id < 1 || post.visibility != 'public') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Only public posts can be shared.')),
      );
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: DarkColors.backgroundColor,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => SendPostSheet(
        post: post,
        repo: repo,
        messenger: messenger,
        actions: actions,
      ),
    );
  }

  @override
  State<SendPostSheet> createState() => _SendPostSheetState();
}

class _SendPostSheetState extends State<SendPostSheet> {
  late final SendPostCubit _people;
  late final PostShareActions _actions;
  final _message = TextEditingController();
  bool _busy = false;
  String? _feedback;

  @override
  void initState() {
    super.initState();
    _actions =
        widget.actions ??
        PostShareActions(text: SendPostSheet.fallbackText(widget.post));
    _people = SendPostCubit(
      post: widget.post,
      repo: widget.repo,
      messenger: widget.messenger,
    )..load();
  }

  @override
  void dispose() {
    _people.close();
    _message.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final sent = await _people.send(_message.text);
    if (!mounted || sent == null || sent.isEmpty) return;
    if (_people.state.selected.isNotEmpty) {
      // Partial failure: keep the sheet open so failed people can be retried.
      messenger.showSnackBar(SnackBar(content: Text(_sentLabel(sent))));
      return;
    }
    navigator.pop();
    messenger.showSnackBar(SnackBar(content: Text(_sentLabel(sent))));
  }

  static String _sentLabel(List<PublicUserModel> sent) => sent.length == 1
      ? 'Sent to ${sent.single.name}'
      : 'Sent to ${sent.length} people';

  Future<void> _external({
    required bool copy,
    required BuildContext anchor,
  }) async {
    if (_busy) return;
    if (copy && !_actions.available) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Post links aren't available yet.")),
      );
      return;
    }
    if (!copy && !_actions.canShare) return;
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
        padding: const EdgeInsets.only(top: 12, bottom: 20),
        child: BlocBuilder<SendPostCubit, SendPostState>(
          bloc: _people,
          builder: (context, state) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Center(child: SheetHandle()),
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: _gutter),
                child: Text(
                  'Send Post',
                  key: const ValueKey('send-post-title'),
                  style: _text.copyWith(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: _gutter),
                child: _search(),
              ),
              const SizedBox(height: 16),
              const Divider(color: _divider, height: 1),
              const SizedBox(height: 14),
              _peopleSection(state),
              const SizedBox(height: 14),
              const Divider(color: _divider, height: 1),
              const SizedBox(height: 14),
              if (state.selected.isEmpty)
                ..._externalActions()
              else
                ..._compose(state),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _search() => TextField(
    key: const ValueKey('send-post-search'),
    onChanged: _people.search,
    style: _text,
    cursorColor: DarkColors.whiteColor,
    textInputAction: TextInputAction.search,
    decoration: InputDecoration(
      hintText: 'Search',
      hintStyle: _text.copyWith(color: DarkColors.greyColor),
      prefixIcon: Center(
        widthFactor: 1,
        heightFactor: 1,
        child: SvgPicture.asset(
          'assets/images/interactions/search-normal.svg',
          key: const ValueKey('send-post-search-icon'),
          width: 20,
          height: 20,
        ),
      ),
      filled: true,
      fillColor: const Color(0xFF141414),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(24),
        borderSide: const BorderSide(color: _divider),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(24),
        borderSide: const BorderSide(color: DarkColors.greyColor),
      ),
    ),
  );

  Widget _peopleSection(SendPostState state) {
    final users = state.visibleUsers;
    final status = !state.validQuery
        ? Text('Search must contain 3–100 characters.', style: _text)
        : state.loading && users.isEmpty
        ? const SizedBox(
            height: 96,
            child: Center(
              child: CircularProgressIndicator(
                semanticsLabel: 'Loading people',
              ),
            ),
          )
        : users.isEmpty && state.error == null
        ? Text(
            state.query.isEmpty
                ? 'No suggested people yet.'
                : 'No people found.',
            style: _text,
          )
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (status != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: _gutter),
            child: status,
          )
        else if (users.isNotEmpty)
          SizedBox(
            // Avatar + gap + two name lines, growing with the text scale.
            height:
                64 + MediaQuery.textScalerOf(context).scale(12 * 1.3 * 2) + 6,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: _gutter),
              itemCount: users.length + (state.hasMore ? 1 : 0),
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                if (index == users.length) {
                  return Center(
                    child: TextButton(
                      onPressed: state.loadingMore ? null : _people.more,
                      child: Text(
                        state.loadingMore ? 'Loading…' : 'More people',
                        style: _text,
                      ),
                    ),
                  );
                }
                final user = users[index];
                return _person(
                  user,
                  selected: state.isSelected(user.id),
                  enabled: !state.sending,
                );
              },
            ),
          ),
        if (state.error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: _gutter),
            child: Column(
              children: [
                Text(state.error!, style: _text, textAlign: TextAlign.center),
                TextButton(
                  onPressed: state.loadingMore
                      ? null
                      : state.hasMore
                      ? _people.more
                      : _people.load,
                  child: Text('Retry people', style: _text),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _person(
    PublicUserModel user, {
    required bool selected,
    required bool enabled,
  }) {
    final onTap = enabled ? () => _people.toggle(user) : null;
    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      label: user.name,
      onTap: onTap,
      excludeSemantics: true,
      child: InkWell(
        key: ValueKey('send-post-user-${user.id}'),
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: SizedBox(
          width: 72,
          child: Column(
            children: [
              SizedBox.square(
                dimension: 52,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    HomeUserAvatar(url: user.avatarUrl, size: 52),
                    if (selected)
                      Positioned(
                        key: ValueKey('send-post-selected-${user.id}'),
                        right: -2,
                        bottom: -2,
                        child: Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            color: DarkColors.primaryColor,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: DarkColors.backgroundColor,
                              width: 2,
                            ),
                          ),
                          child: const Icon(
                            Icons.check,
                            size: 11,
                            color: DarkColors.whiteColor,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                user.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: _text.copyWith(fontSize: 12, height: 1.3),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _externalActions() => [
    Padding(
      padding: const EdgeInsets.symmetric(horizontal: _gutter - 8),
      child: Row(
        children: [
          Builder(
            builder: (anchor) => _action(
              'Copy Link',
              SvgPicture.asset(
                'assets/images/interactions/link.svg',
                width: 46,
                height: 46,
              ),
              _busy ? null : () => _external(copy: true, anchor: anchor),
            ),
          ),
          Builder(
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
        ],
      ),
    ),
    if (_feedback != null) ...[
      const SizedBox(height: 8),
      Semantics(
        liveRegion: true,
        child: Text(_feedback!, style: _text, textAlign: TextAlign.center),
      ),
    ],
    if (_busy)
      const LinearProgressIndicator(semanticsLabel: 'Opening share action'),
  ];

  List<Widget> _compose(SendPostState state) => [
    Padding(
      padding: const EdgeInsets.symmetric(horizontal: _gutter),
      child: TextField(
        key: const ValueKey('send-post-message'),
        controller: _message,
        enabled: !state.sending,
        style: _text,
        cursorColor: DarkColors.whiteColor,
        minLines: 1,
        maxLines: 4,
        maxLength: 1000,
        keyboardType: TextInputType.multiline,
        textCapitalization: TextCapitalization.sentences,
        // The global InputDecorationTheme fills fields white with an outline;
        // every fill/border slot is overridden so the field is transparent.
        decoration: InputDecoration(
          hintText: 'Write Message',
          hintStyle: _text.copyWith(color: DarkColors.greyColor),
          filled: false,
          fillColor: Colors.transparent,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          disabledBorder: InputBorder.none,
          errorBorder: InputBorder.none,
          focusedErrorBorder: InputBorder.none,
          counterText: '',
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    ),
    if (state.failures.isNotEmpty) ...[
      const SizedBox(height: 12),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: _gutter),
        child: Semantics(
          liveRegion: true,
          child: Column(
            key: const ValueKey('send-post-failures'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final user in state.selected)
                if (state.failures[user.id] case final message?)
                  Text(
                    '${user.name}: $message',
                    style: _text.copyWith(
                      fontSize: 12,
                      color: DarkColors.primaryColor,
                    ),
                  ),
            ],
          ),
        ),
      ),
    ],
    const SizedBox(height: 48),
    Padding(
      padding: const EdgeInsets.symmetric(horizontal: _gutter),
      child: CustomButton(
        key: const ValueKey('send-post-send'),
        title: state.sending ? 'Sending…' : 'Send',
        onPressed: state.sending ? null : _send,
      ),
    ),
  ];

  Widget _action(String label, Widget icon, VoidCallback? onPressed) =>
      SizedBox(
        width: 96,
        child: TextButton(
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
                textAlign: TextAlign.center,
                style: _text.copyWith(
                  fontSize: 12,
                  color: onPressed == null
                      ? DarkColors.greyColor
                      : DarkColors.whiteColor,
                ),
              ),
            ],
          ),
        ),
      );
}
