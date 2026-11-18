import 'package:flutter/material.dart';
import 'package:travibe/core/theme/dark_colors.dart';

/// `@handle` inside story text. Not preceded by a word character, so emails
/// stay plain. Dots are allowed inside a handle but never at its end.
final storyMentionPattern = RegExp(
  r'(?<![A-Za-z0-9_])@([A-Za-z0-9_]+(?:\.[A-Za-z0-9_]+)*)',
);

/// The text ranges of every `@handle` in [text].
List<TextRange> storyMentionRanges(String text) => [
  for (final match in storyMentionPattern.allMatches(text))
    TextRange(start: match.start, end: match.end),
];

/// [text] as one span whose `@handle` parts are orange. Sizes match the plain
/// span exactly; only the colour changes. [underline] marks an IME composing
/// range.
TextSpan storyMentionTextSpan(
  String text,
  TextStyle? style, {
  TextRange underline = TextRange.empty,
}) {
  final mentions = storyMentionRanges(text);
  final hasUnderline =
      underline.isValid &&
      !underline.isCollapsed &&
      underline.end <= text.length;
  if (mentions.isEmpty && !hasUnderline) {
    return TextSpan(text: text, style: style);
  }
  final cuts = <int>{0, text.length};
  for (final range in mentions) {
    cuts
      ..add(range.start)
      ..add(range.end);
  }
  if (hasUnderline) {
    cuts
      ..add(underline.start)
      ..add(underline.end);
  }
  final points = cuts.toList()..sort();
  const highlight = TextStyle(color: DarkColors.primaryColor);
  const composing = TextStyle(decoration: TextDecoration.underline);
  return TextSpan(
    style: style,
    children: [
      for (var i = 0; i < points.length - 1; i++)
        if (points[i] < points[i + 1])
          TextSpan(
            text: text.substring(points[i], points[i + 1]),
            style: _merge(
              mentions.any(
                    (r) => r.start <= points[i] && points[i + 1] <= r.end,
                  )
                  ? highlight
                  : null,
              hasUnderline &&
                      underline.start <= points[i] &&
                      points[i + 1] <= underline.end
                  ? composing
                  : null,
            ),
          ),
    ],
  );
}

TextStyle? _merge(TextStyle? a, TextStyle? b) =>
    a == null ? b : (b == null ? a : a.merge(b));

/// The `@query` being typed right before the caret, if any.
class StoryMentionQuery {
  const StoryMentionQuery({required this.start, required this.query});

  /// Index of the `@`.
  final int start;

  /// What follows the `@` up to the caret (may be empty).
  final String query;
}

final _typingMention = RegExp(r'(?:^|[^A-Za-z0-9_])@([A-Za-z0-9_.]{0,30})$');

StoryMentionQuery? storyMentionQueryAt(TextEditingValue value) {
  final selection = value.selection;
  if (!selection.isValid ||
      !selection.isCollapsed ||
      selection.baseOffset > value.text.length) {
    return null;
  }
  final before = value.text.substring(0, selection.baseOffset);
  final match = _typingMention.firstMatch(before);
  if (match == null) return null;
  final query = match.group(1)!;
  return StoryMentionQuery(
    start: selection.baseOffset - query.length - 1,
    query: query,
  );
}

/// Replaces [query] (from its `@` to the caret) with `@username ` and puts the
/// caret after the trailing space.
TextEditingValue insertStoryMention(
  TextEditingValue value,
  StoryMentionQuery query,
  String username,
) {
  final caret = value.selection.baseOffset;
  final mention = '@$username ';
  final after = value.text.substring(caret);
  // Don't double the space when the text already continues with one.
  final insert = after.startsWith(' ') ? mention.trimRight() : mention;
  final text = value.text.replaceRange(query.start, caret, insert);
  final offset = query.start + insert.length + (after.startsWith(' ') ? 1 : 0);
  return TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: offset),
  );
}

/// Highlights `@handle` in orange while typing.
class StoryMentionTextController extends TextEditingController {
  StoryMentionTextController({super.text});

  StoryMentionQuery? get activeQuery => storyMentionQueryAt(value);

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) => storyMentionTextSpan(
    text,
    style,
    underline: withComposing && value.isComposingRangeValid
        ? value.composing
        : TextRange.empty,
  );
}
