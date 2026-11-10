import 'package:flutter/material.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:travibe/core/widgets/sheet_handle.dart';

Future<String?> showStoryTextEntry(BuildContext context, {String? text}) =>
    showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: DarkColors.backgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _StoryTextEntry(text: text),
    );

class _StoryTextEntry extends StatefulWidget {
  const _StoryTextEntry({this.text});
  final String? text;
  @override
  State<_StoryTextEntry> createState() => _StoryTextEntryState();
}

class _StoryTextEntryState extends State<_StoryTextEntry> {
  late final _controller = TextEditingController(text: widget.text);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SheetHandle(),
          Row(
            children: [
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: DarkColors.primaryColor,
                  textStyle: const TextStyle(
                    fontFamily: 'Plus Jakarta Sans',
                    fontSize: 14,
                    letterSpacing: 0,
                  ),
                ),
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              Expanded(
                child: Text(
                  widget.text == null ? 'Add text' : 'Edit text',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontFamily: 'Plus Jakarta Sans',
                  ),
                ),
              ),
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: DarkColors.primaryColor,
                  textStyle: const TextStyle(
                    fontFamily: 'Plus Jakarta Sans',
                    fontSize: 14,
                    letterSpacing: 0,
                  ),
                ),
                key: const ValueKey('story-text-done'),
                onPressed: () => Navigator.pop(context, _controller.text),
                child: const Text('Done'),
              ),
            ],
          ),
          TextField(
            key: const ValueKey('story-text-input'),
            controller: _controller,
            autofocus: true,
            minLines: 2,
            maxLines: 5,
            keyboardType: TextInputType.multiline,
            textCapitalization: TextCapitalization.sentences,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontFamily: 'Plus Jakarta Sans',
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
        ],
      ),
    ),
  );
}
