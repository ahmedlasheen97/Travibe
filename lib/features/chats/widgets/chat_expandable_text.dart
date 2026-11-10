import 'package:flutter/material.dart';

/// Layout-measured preview, with original Unicode text retained for selection.
class ChatExpandableText extends StatefulWidget {
  const ChatExpandableText({
    super.key,
    required this.text,
    required this.messageId,
  });
  final String text, messageId;
  @override
  State<ChatExpandableText> createState() => _ChatExpandableTextState();
}

class _ChatExpandableTextState extends State<ChatExpandableText> {
  static const _style = TextStyle(
    color: Colors.white,
    fontSize: 15,
    height: 1.5,
  );
  bool _expanded = false, _overflows = false;
  Object? _measurement;
  Object get _storage =>
      ('chat-message-expansion', widget.messageId, widget.text);
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _expanded =
        PageStorage.maybeOf(
          context,
        )?.readState(context, identifier: _storage) ==
        true;
  }

  @override
  void didUpdateWidget(covariant ChatExpandableText old) {
    super.didUpdateWidget(old);
    if (old.messageId != widget.messageId || old.text != widget.text) {
      _measurement = null;
      _expanded =
          PageStorage.maybeOf(
            context,
          )?.readState(context, identifier: _storage) ==
          true;
    }
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    PageStorage.maybeOf(
      context,
    )?.writeState(context, _expanded, identifier: _storage);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final scaler = MediaQuery.textScalerOf(context),
          direction = Directionality.of(context);
      final measurement = (
        widget.text,
        constraints.maxWidth,
        scaler,
        direction,
      );
      if (measurement != _measurement) {
        _measurement = measurement;
        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: _style),
          maxLines: 6,
          textScaler: scaler,
          textDirection: direction,
        )..layout(maxWidth: constraints.maxWidth);
        _overflows = painter.didExceedMaxLines;
        painter.dispose();
      }
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_expanded)
            SelectionArea(child: Text(widget.text, style: _style))
          else
            Text(
              widget.text,
              style: _style,
              maxLines: 6,
              overflow: TextOverflow.ellipsis,
            ),
          if (_overflows)
            TextButton(
              onPressed: _toggle,
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                padding: EdgeInsets.zero,
                minimumSize: const Size(44, 40),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                _expanded ? 'Read Less' : 'Read More...',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      );
    },
  );
}
