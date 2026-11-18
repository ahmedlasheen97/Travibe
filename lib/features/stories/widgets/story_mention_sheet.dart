import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/models/public_user_model.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:travibe/core/widgets/app_loaders.dart';
import 'package:travibe/core/widgets/sheet_handle.dart';
import 'package:travibe/core/widgets/travibe_toast.dart';
import 'package:travibe/features/stories/data/story_elements.dart';
import 'package:travibe/features/home/widgets/home_user_avatar.dart';
import 'package:travibe/features/stories/data/mentions_repo.dart';

/// What the Mention sheet's "Add" returns.
class StoryMentionSelection {
  const StoryMentionSelection({
    required this.users,
    required this.allowReshare,
  });
  final List<PublicUserModel> users;
  final bool allowReshare;
}

/// The @ tool's multi-select sheet (Figma `mention_sheet.png`). [selected]
/// are the users already mentioned; they start checked. Picked people are
/// mentioned without anything drawn on the story.
Future<StoryMentionSelection?> showStoryMentionSheet(
  BuildContext context, {
  MentionsRepo? repo,
  List<PublicUserModel> selected = const [],
  bool allowReshare = true,
  bool showReshareToggle = false,
}) => showModalBottomSheet<StoryMentionSelection>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: DarkColors.backgroundColor,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
  ),
  builder: (_) => StoryMentionSheet(
    repo: repo ?? MentionsRepo(),
    selected: selected,
    allowReshare: allowReshare,
    showReshareToggle: showReshareToggle,
  ),
);

/// A minimal user for a mention known only by id and username.
PublicUserModel storyMentionUser(int id, String username) => PublicUserModel(
  id: '$id',
  name: username,
  username: username,
  isFollowing: false,
  isBlocked: false,
  followersCount: 0,
  followingCount: 0,
);

const _font = 'Plus Jakarta Sans';

class StoryMentionSheet extends StatefulWidget {
  const StoryMentionSheet({
    super.key,
    required this.repo,
    this.selected = const [],
    this.allowReshare = true,
    this.showReshareToggle = false,
  });
  final MentionsRepo repo;
  final List<PublicUserModel> selected;
  final bool allowReshare;

  /// Only for a public story from a public account (the API rejects
  /// `allow_mention_reshare` otherwise).
  final bool showReshareToggle;

  @override
  State<StoryMentionSheet> createState() => _StoryMentionSheetState();
}

class _StoryMentionSheetState extends State<StoryMentionSheet> {
  static const _debounce = Duration(milliseconds: 300);
  final _controller = TextEditingController();
  Timer? _timer;
  int _generation = 0;
  bool _loading = true;
  String? _error;
  List<PublicUserModel> _results = const [];

  /// Checked users by id, in the order they were checked.
  late final Map<String, PublicUserModel> _checked = {
    for (final user in widget.selected) user.id: user,
  };
  late bool _allowReshare = widget.allowReshare;

  @override
  void initState() {
    super.initState();
    _search('', _generation);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  String get _term => _controller.text.trim().replaceFirst(RegExp('^@'), '');

  void _changed(String _) {
    _timer?.cancel();
    final generation = ++_generation;
    setState(() => _loading = true);
    _timer = Timer(_debounce, () => _search(_term, generation));
  }

  Future<void> _search(String term, int generation) async {
    try {
      final users = await widget.repo.suggestions(q: term);
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _error = null;
        _results = users;
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _results = const [];
        _error = error is ApiError
            ? error.message
            : 'Unable to load people. Please try again.';
      });
    }
  }

  /// With no search, already-mentioned users stay listed (checked) on top
  /// even if the suggestions don't include them.
  List<PublicUserModel> get _rows {
    if (_term.isNotEmpty) return _results;
    final ids = {for (final user in _results) user.id};
    return [
      for (final user in _checked.values)
        if (!ids.contains(user.id)) user,
      ..._results,
    ];
  }

  void _toggle(PublicUserModel user) {
    if (!_checked.containsKey(user.id) &&
        _checked.length >= StoryElements.maxMentions) {
      TravibeToast.show(
        context,
        const TravibeToastData.info(
          'You can mention up to ${StoryElements.maxMentions} people.',
        ),
      );
      return;
    }
    setState(() {
      if (_checked.remove(user.id) == null) _checked[user.id] = user;
    });
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    final Widget body;
    if (_loading && rows.isEmpty) {
      body = const Center(
        child: AppActivityIndicator(key: ValueKey('story-mention-loading')),
      );
    } else if (_error != null && rows.isEmpty) {
      body = _message(_error!);
    } else if (rows.isEmpty) {
      body = _message(
        _term.isEmpty
            ? 'Follow people to mention them, or search by name.'
            : 'No people found.',
      );
    } else {
      body = ListView.builder(
        key: const ValueKey('story-mention-list'),
        padding: const EdgeInsets.only(top: 8),
        itemCount: rows.length,
        itemBuilder: (context, index) {
          final user = rows[index];
          final checked = _checked.containsKey(user.id);
          return StoryMentionUserRow(
            key: ValueKey('story-mention-user-${user.id}'),
            user: user,
            trailing: _StoryCheckbox(
              key: ValueKey('story-mention-check-${user.id}'),
              checked: checked,
            ),
            selected: checked,
            onTap: () => _toggle(user),
          );
        },
      );
    }
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.6,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Center(child: SheetHandle()),
                const SizedBox(height: 20),
                const Text(
                  'Mention',
                  style: TextStyle(
                    color: Colors.white,
                    fontFamily: _font,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),
                _searchField(),
                Expanded(child: body),
                if (widget.showReshareToggle) ...[
                  const SizedBox(height: 8),
                  StoryReshareToggle(
                    value: _allowReshare,
                    onChanged: (value) => setState(() => _allowReshare = value),
                  ),
                ],
                const SizedBox(height: 12),
                FilledButton(
                  key: const ValueKey('story-mention-add'),
                  onPressed: _checked.isEmpty
                      ? null
                      : () => Navigator.pop(
                          context,
                          StoryMentionSelection(
                            users: List.unmodifiable(_checked.values),
                            allowReshare: _allowReshare,
                          ),
                        ),
                  style: FilledButton.styleFrom(
                    backgroundColor: DarkColors.primaryColor,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: DarkColors.primaryColor.withValues(
                      alpha: 0.4,
                    ),
                    disabledForegroundColor: Colors.white60,
                    minimumSize: const Size.fromHeight(52),
                    shape: const StadiumBorder(),
                    textStyle: const TextStyle(
                      fontFamily: _font,
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  child: const Text('Add'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _searchField() {
    OutlineInputBorder border() => OutlineInputBorder(
      borderRadius: BorderRadius.circular(28),
      borderSide: const BorderSide(color: Color(0xFF2E2E2E)),
    );
    return TextField(
      key: const ValueKey('story-mention-search'),
      controller: _controller,
      onChanged: _changed,
      maxLength: MentionsRepo.maxQueryLength,
      textInputAction: TextInputAction.search,
      cursorColor: Colors.white,
      style: const TextStyle(color: Colors.white, fontSize: 15),
      decoration: InputDecoration(
        counterText: '',
        hintText: 'Search people',
        hintStyle: TextStyle(
          color: Colors.white.withValues(alpha: 0.5),
          fontSize: 15,
          fontFamily: _font,
        ),
        prefixIcon: Padding(
          padding: const EdgeInsets.all(14),
          child: SvgPicture.asset(
            'assets/images/interactions/search-normal.svg',
            width: 20,
            height: 20,
          ),
        ),
        filled: true,
        fillColor: const Color(0xFF141414),
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
        border: border(),
        enabledBorder: border(),
        focusedBorder: border(),
      ),
    );
  }

  Widget _message(String text) => Center(
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: const TextStyle(color: Colors.white54, fontFamily: _font),
    ),
  );
}

/// Avatar, name and @username; shared by the Mention sheet and the inline
/// suggestions while typing.
class StoryMentionUserRow extends StatelessWidget {
  const StoryMentionUserRow({
    super.key,
    required this.user,
    required this.onTap,
    this.trailing,
    this.selected,
  });
  final PublicUserModel user;
  final VoidCallback onTap;
  final Widget? trailing;

  /// Non-null for checkable rows (announced as a checkbox).
  final bool? selected;

  @override
  Widget build(BuildContext context) => Semantics(
    button: selected == null,
    checked: selected,
    label: '${user.name}, ${user.handle}',
    excludeSemantics: true,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            HomeUserAvatar(url: user.avatarUrl, size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    user.name.isEmpty ? user.handle : user.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontFamily: _font,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    user.handle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white54,
                      fontFamily: _font,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 12), trailing!],
          ],
        ),
      ),
    ),
  );
}

/// "People you mention can reshare this story" (Figma orange switch).
class StoryReshareToggle extends StatelessWidget {
  const StoryReshareToggle({
    super.key,
    required this.value,
    required this.onChanged,
  });
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: Row(
      children: [
        const Expanded(
          child: Text(
            'People you mention can reshare this story',
            style: TextStyle(
              color: Colors.white,
              fontFamily: _font,
              fontSize: 14,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Switch(
          key: const ValueKey('story-reshare-toggle'),
          value: value,
          onChanged: onChanged,
          activeThumbColor: Colors.white,
          activeTrackColor: DarkColors.primaryColor,
          inactiveThumbColor: Colors.white,
          inactiveTrackColor: const Color(0xFF3B3B3B),
        ),
      ],
    ),
  );
}

class _StoryCheckbox extends StatelessWidget {
  const _StoryCheckbox({super.key, required this.checked});
  final bool checked;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 120),
    width: 22,
    height: 22,
    decoration: BoxDecoration(
      color: checked ? DarkColors.primaryColor : Colors.transparent,
      borderRadius: BorderRadius.circular(4),
      border: Border.all(
        color: checked ? DarkColors.primaryColor : Colors.white,
        width: 1.5,
      ),
    ),
    child: checked
        ? const Icon(Icons.check_rounded, size: 16, color: Colors.white)
        : null,
  );
}
