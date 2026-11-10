import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/features/stories/widgets/story_glass.dart';

/// Ephemeral, current-story UI only. No repository, persistence or send action.
class StoryReplyComposer extends StatefulWidget {
  const StoryReplyComposer({
    super.key,
    required this.storyId,
    required this.onActiveChanged,
  });
  final int storyId;
  final ValueChanged<bool> onActiveChanged;
  @override
  State<StoryReplyComposer> createState() => _StoryReplyComposerState();
}

class _StoryReplyComposerState extends State<StoryReplyComposer>
    with WidgetsBindingObserver {
  final _text = TextEditingController();
  final _focus = FocusNode();
  final _session = PreferencesManager();
  bool _keyboardVisible = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _focus.addListener(_focusChanged);
    _session.addListener(_sessionChanged);
  }

  void _focusChanged() {
    widget.onActiveChanged(_focus.hasFocus);
    if (mounted) setState(() {});
  }

  void _sessionChanged() {
    _text.clear();
    _focus.unfocus();
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant StoryReplyComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.storyId != widget.storyId) {
      _text.clear();
      _focus.unfocus();
    }
  }

  @override
  void didChangeMetrics() {
    final visible = View.of(context).viewInsets.bottom > 0;
    if (_keyboardVisible && !visible) _focus.unfocus();
    _keyboardVisible = visible;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _session.removeListener(_sessionChanged);
    _focus.removeListener(_focusChanged);
    _focus.dispose();
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      StoryGlass(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: TextField(
            key: const ValueKey('story-reply-field'),
            controller: _text,
            focusNode: _focus,
            style: const TextStyle(
              color: Colors.white,
              fontFamily: 'Plus Jakarta Sans',
              fontSize: 14,
            ),
            textInputAction: TextInputAction.done,
            onEditingComplete: _focus.unfocus,
            onTapOutside: (_) => _focus.unfocus(),
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Send Message',
              hintStyle: const TextStyle(
                color: Colors.white70,
                fontFamily: 'Plus Jakarta Sans',
                fontSize: 14,
              ),
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                vertical: 14,
                horizontal: 12,
              ),
              prefixIcon: Center(
                widthFactor: 1,
                heightFactor: 1,
                child: SvgPicture.asset(
                  'assets/images/interactions/happyemoji.svg',
                  width: 20,
                  height: 20,
                  excludeFromSemantics: true,
                ),
              ),
              prefixIconConstraints: const BoxConstraints(minWidth: 36),
             suffixIcon: _focus.hasFocus
              ? IconButton(
          tooltip: 'Send message (coming soon)',
          icon: SvgPicture.asset(
            'assets/images/interactions/send.svg',
            width: 20,
            height: 20,
          ),
          onPressed: null, // Disabled until Story Reply API is ready
                )
              : null,
            ),
          ),
        ),
      ),
      if (_focus.hasFocus || _text.text.isNotEmpty)
        const Padding(
          padding: EdgeInsets.only(top: 6),
          child: Text(
            'Replies are not available yet.',
            style: TextStyle(
              fontFamily: 'Plus Jakarta Sans',
              fontSize: 11,
              color: Colors.white70,
            ),
          ),
        ),
    ],
  );
}
