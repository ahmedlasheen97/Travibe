import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:travibe/core/theme/dark_colors.dart';

/// Home-only caption presentation. No feed or transport dependencies.
class HomePostCaption extends StatefulWidget {
  const HomePostCaption({
    super.key,
    required this.text,
    required this.style,
    this.postId,
  });
  final String text;
  final String? postId;
  final TextStyle style;
  static const collapsedLines = 4;

  @override
  State<HomePostCaption> createState() => _HomePostCaptionState();
}

class _HomePostCaptionState extends State<HomePostCaption> {
  late final _link = TapGestureRecognizer()..onTap = _toggle;
  bool _expanded = false;
  bool _overflows = false;
  String _prefix = '';
  Object? _measurementKey;
  Object? get _storageKey => widget.postId == null
      ? null
      : ('home-caption', widget.postId, widget.text);

  void _restore() {
    final key = _storageKey;
    _expanded =
        key != null &&
        PageStorage.maybeOf(context)?.readState(context, identifier: key) ==
            true;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _restore();
  }

  @override
  void didUpdateWidget(covariant HomePostCaption oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.postId != oldWidget.postId || widget.text != oldWidget.text) {
      _measurementKey = null;
      _restore();
    }
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    final key = _storageKey;
    if (key != null) {
      PageStorage.maybeOf(
        context,
      )?.writeState(context, _expanded, identifier: key);
    }
  }

  @override
  void dispose() {
    _link.dispose();
    super.dispose();
  }

  // Let Flutter's bidi engine handle runs within a paragraph whose base
  // direction follows the caption's first letter, including Arabic/Hebrew.
  static final _letter = RegExp(r'\p{L}', unicode: true);
  TextDirection _direction(BuildContext context) {
    final first = _letter.firstMatch(widget.text)?.group(0)?.runes.first;
    if (first == null) return Directionality.of(context);
    final rtl =
        (first >= 0x590 && first <= 0x8ff) ||
        (first >= 0xfb1d && first <= 0xfdff) ||
        (first >= 0xfe70 && first <= 0xfefc) ||
        (first >= 0x1ee00 && first <= 0x1eeff);
    return rtl ? TextDirection.rtl : TextDirection.ltr;
  }

  TextSpan _collapsedSpan(TextStyle style, String prefix) => TextSpan(
    style: style,
    children: [
      // Assistive technology retains the complete original caption.
      TextSpan(text: '$prefix ', semanticsLabel: widget.text),
      TextSpan(
        text: 'read more...',
        style: const TextStyle(
          color: DarkColors.primaryColor,
          fontWeight: FontWeight.w600,
        ),
        recognizer: _link,
      ),
    ],
  );

  void _measure(
    double width,
    TextStyle style,
    TextScaler scaler,
    TextDirection direction,
    Locale? locale,
  ) {
    final key = (widget.text, width, style, scaler, direction, locale);
    if (key == _measurementKey) return;
    _measurementKey = key;
    final painter = TextPainter(
      text: TextSpan(text: widget.text, style: style),
      maxLines: HomePostCaption.collapsedLines,
      textDirection: direction,
      textScaler: scaler,
      locale: locale,
    )..layout(maxWidth: width);
    try {
      _overflows = painter.didExceedMaxLines;
      if (!_overflows) return;
      // Search only grapheme boundaries: never split emoji/ZWJ/combining runs.
      final graphemes = widget.text.characters.toList(growable: false);
      var low = 0;
      var high = graphemes.length;
      while (low < high) {
        final middle = (low + high + 1) ~/ 2;
        final prefix = graphemes.take(middle).join().trimRight();
        painter.text = _collapsedSpan(style, prefix);
        painter.layout(maxWidth: width);
        if (painter.didExceedMaxLines) {
          high = middle - 1;
        } else {
          low = middle;
        }
      }
      _prefix = graphemes.take(low).join().trimRight();
    } finally {
      painter.dispose();
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final style = DefaultTextStyle.of(context).style.merge(widget.style);
      final scaler = MediaQuery.textScalerOf(context);
      final direction = _direction(context);
      final locale = Localizations.maybeLocaleOf(context);
      _measure(constraints.maxWidth, style, scaler, direction, locale);
      final span = _overflows && !_expanded
          ? _collapsedSpan(style, _prefix)
          : TextSpan(
              style: style,
              children: [
                TextSpan(text: widget.text),
                if (_overflows)
                  TextSpan(
                    text: ' show less',
                    style: const TextStyle(
                      color: DarkColors.primaryColor,
                      fontWeight: FontWeight.w600,
                    ),
                    recognizer: _link,
                  ),
              ],
            );
      return Text.rich(
        span,
        key: const ValueKey('home-caption-text'),
        textDirection: direction,
        textScaler: scaler,
        locale: locale,
        maxLines: _expanded ? null : HomePostCaption.collapsedLines,
        overflow: TextOverflow.clip,
      );
    },
  );
}
