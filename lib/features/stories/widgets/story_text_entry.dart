import 'dart:async';

import 'package:flutter/material.dart';
import 'package:travibe/core/constants/feature_flags.dart';
import 'package:travibe/core/models/public_user_model.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:travibe/core/widgets/sheet_handle.dart';
import 'package:travibe/features/stories/data/mentions_repo.dart';
import 'package:travibe/features/stories/widgets/story_glass.dart';
import 'package:travibe/features/stories/widgets/story_mention_sheet.dart';
import 'package:travibe/features/stories/widgets/story_mention_text.dart';

class StoryTextEntryResult {
  const StoryTextEntryResult({required this.text, required this.allowReshare});
  final String text;
  final bool allowReshare;
}

/// Full-screen text entry over the dimmed story (Figma `mention_typing.png`).
/// Typing `@` shows matching people above the keyboard; picking one inserts
/// `@username`, highlighted in orange.
Future<StoryTextEntryResult?> showStoryTextEntry(
  BuildContext context, {
  String? text,
  MentionsRepo? mentionsRepo,
  bool allowReshare = true,
  bool enableReshare = kEnableStoryReshare,
}) => Navigator.of(context).push<StoryTextEntryResult>(
  PageRouteBuilder(
    opaque: false,
    barrierDismissible: false,
    transitionDuration: const Duration(milliseconds: 150),
    reverseTransitionDuration: const Duration(milliseconds: 120),
    pageBuilder: (_, _, _) => StoryTextEntry(
      text: text,
      repo: mentionsRepo ?? MentionsRepo(),
      allowReshare: allowReshare,
      enableReshare: enableReshare,
    ),
    transitionsBuilder: (_, animation, _, child) =>
        FadeTransition(opacity: animation, child: child),
  ),
);

const _font = 'Plus Jakarta Sans';

class StoryTextEntry extends StatefulWidget {
  const StoryTextEntry({
    super.key,
    this.text,
    required this.repo,
    this.allowReshare = true,
    this.enableReshare = kEnableStoryReshare,
  });
  final String? text;
  final MentionsRepo repo;
  final bool allowReshare;
  final bool enableReshare;
  @override
  State<StoryTextEntry> createState() => _StoryTextEntryState();
}

class _StoryTextEntryState extends State<StoryTextEntry> {
  static const _debounce = Duration(milliseconds: 250);
  late final _controller = StoryMentionTextController(text: widget.text);
  late bool _allowReshare = widget.allowReshare;
  Timer? _timer;
  int _generation = 0;
  String? _query;
  List<PublicUserModel> _suggestions = const [];

  @override
  void initState() {
    super.initState();
    _controller.addListener(_watchMention);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _watchMention() {
    final query = _controller.activeQuery?.query;
    if (query == _query) return;
    _query = query;
    _timer?.cancel();
    final generation = ++_generation;
    if (query == null) {
      setState(() => _suggestions = const []);
      return;
    }
    _timer = Timer(_debounce, () => _load(query, generation));
  }

  Future<void> _load(String query, int generation) async {
    try {
      final users = await widget.repo.suggestions(q: query, perPage: 10);
      if (!mounted || generation != _generation) return;
      setState(() => _suggestions = users);
    } catch (_) {
      // Suggestions are optional; the typed @handle still works as text.
      if (!mounted || generation != _generation) return;
      setState(() => _suggestions = const []);
    }
  }

  void _pick(PublicUserModel user) {
    final query = _controller.activeQuery;
    final username = user.username;
    if (query == null || username == null || username.isEmpty) return;
    _controller.value = insertStoryMention(_controller.value, query, username);
  }

  void _done() => Navigator.pop(
    context,
    StoryTextEntryResult(text: _controller.text, allowReshare: _allowReshare),
  );

  @override
  Widget build(BuildContext context) {
    final suggesting = _query != null && _suggestions.isNotEmpty;
    return Material(
      color: Colors.black.withValues(alpha: 0.6),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
              child: Row(
                children: [
                  StoryGlass(
                    child: IconButton(
                      key: const ValueKey('story-text-cancel'),
                      tooltip: 'Cancel',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close, color: Colors.white),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      widget.text == null ? 'Add text' : 'Edit text',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontFamily: _font,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  TextButton(
                    key: const ValueKey('story-text-done'),
                    style: TextButton.styleFrom(
                      foregroundColor: DarkColors.primaryColor,
                      textStyle: const TextStyle(
                        fontFamily: _font,
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0,
                      ),
                    ),
                    onPressed: _done,
                    child: const Text('Done'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: TextField(
                    key: const ValueKey('story-text-input'),
                    controller: _controller,
                    autofocus: true,
                    minLines: 1,
                    maxLines: 6,
                    textAlign: TextAlign.center,
                    keyboardType: TextInputType.multiline,
                    textCapitalization: TextCapitalization.sentences,
                    cursorColor: Colors.white,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w600,
                      fontFamily: _font,
                    ),
                    decoration: const InputDecoration(
                      hintText: 'Write something…',
                      hintStyle: TextStyle(color: Colors.white54),
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                    ),
                  ),
                ),
              ),
            ),
            if (suggesting) _suggestionsPanel(),
            // Keep the panel just above the keyboard.
            SizedBox(height: MediaQuery.viewInsetsOf(context).bottom),
          ],
        ),
      ),
    );
  }

  Widget _suggestionsPanel() => Container(
    key: const ValueKey('story-mention-suggestions'),
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * 0.35,
    ),
    decoration: const BoxDecoration(
      color: DarkColors.backgroundColor,
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SheetHandle(),
        const SizedBox(height: 8),
        Flexible(
          child: ListView.builder(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            itemCount: _suggestions.length,
            itemBuilder: (context, index) {
              final user = _suggestions[index];
              return StoryMentionUserRow(
                key: ValueKey('story-mention-suggestion-${user.id}'),
                user: user,
                onTap: () => _pick(user),
              );
            },
          ),
        ),
        if (widget.enableReshare)
          StoryReshareToggle(
            value: _allowReshare,
            onChanged: (value) => setState(() => _allowReshare = value),
          ),
      ],
    ),
  );
}
