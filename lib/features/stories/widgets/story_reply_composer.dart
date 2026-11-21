import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/features/stories/widgets/story_glass.dart';

/// Reply field for the current story. Not persisted; [onSend] does the
/// request and returns true when the reply was sent (the text is then
/// cleared). On false the text stays so the user can try again.
class StoryReplyComposer extends StatefulWidget {
  const StoryReplyComposer({
    super.key,
    required this.storyId,
    required this.onActiveChanged,
    this.onSend,
  });
  final int storyId;
  final ValueChanged<bool> onActiveChanged;

  /// Null hides the send button.
  final Future<bool> Function(String text)? onSend;
  @override
  State<StoryReplyComposer> createState() => _StoryReplyComposerState();
}

class _StoryReplyComposerState extends State<StoryReplyComposer>
    with WidgetsBindingObserver {
  final _text = TextEditingController();
  final _focus = FocusNode();
  final _session = PreferencesManager();
  bool _keyboardVisible = false;
  bool _sending = false;
  int _sendGeneration = 0;

  bool get _canSend =>
      widget.onSend != null && !_sending && _text.text.trim().isNotEmpty;

  Future<void> _send() async {
    if (!_canSend) return;
    final generation = ++_sendGeneration;
    setState(() => _sending = true);
    final sent = await widget.onSend!(_text.text.trim());
    // A story or account change while sending already reset the field.
    if (!mounted || generation != _sendGeneration) return;
    setState(() => _sending = false);
    if (sent) {
      _text.clear();
      _focus.unfocus();
    }
  }

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
    _sendGeneration++;
    _sending = false;
    _text.clear();
    _focus.unfocus();
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant StoryReplyComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.storyId != widget.storyId) {
      _sendGeneration++;
      _sending = false;
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
            readOnly: _sending,
            maxLength: 5000,
            textInputAction: widget.onSend == null
                ? TextInputAction.done
                : TextInputAction.send,
            onEditingComplete: widget.onSend == null ? _focus.unfocus : _send,
            onTapOutside: (_) => _focus.unfocus(),
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Send Message',
              hintStyle: const TextStyle(
                color: Colors.white70,
                fontFamily: 'Plus Jakarta Sans',
                fontSize: 14,
              ),
              counterText: '',
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
              suffixIcon: _focus.hasFocus && widget.onSend != null
                  ? _sending
                        ? const Padding(
                            padding: EdgeInsets.all(14),
                            child: SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            ),
                          )
                        : IconButton(
                            key: const ValueKey('story-reply-send'),
                            tooltip: 'Send reply',
                            icon: SvgPicture.asset(
                              'assets/images/interactions/send.svg',
                              width: 20,
                              height: 20,
                            ),
                            onPressed: _canSend ? _send : null,
                          )
                  : null,
            ),
          ),
        ),
      ),
    ],
  );
}
