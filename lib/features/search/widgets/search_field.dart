import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class SearchField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClear;

  const SearchField({
    super.key,
    required this.controller,
    required this.onChanged,
    required this.onSubmitted,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    OutlineInputBorder border() => OutlineInputBorder(
      borderRadius: BorderRadius.circular(28),
      borderSide: const BorderSide(color: Color(0xFF2E2E2E)),
    );

    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) => TextField(
        controller: controller,
        autofocus: true,
        textInputAction: TextInputAction.search,
        keyboardType: TextInputType.text,
        maxLines: 1,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        cursorColor: Colors.white,
        style: const TextStyle(color: Colors.white, fontSize: 15),
        decoration: InputDecoration(
          hintText: 'Search for travelers, posts..',
          hintStyle: TextStyle(
            color: Colors.white.withValues(alpha: 0.5),
            fontSize: 15,
          ),
          prefixIcon: Padding(
            padding: const EdgeInsets.all(14),
            child: SvgPicture.asset(
              'assets/images/interactions/search-normal.svg',
              width: 20,
              height: 20,
            ),
          ),
          suffixIcon: value.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white70),
                  onPressed: onClear,
                  tooltip: 'Clear search',
                ),
          filled: true,
          fillColor: const Color(0xFF141414),
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
          border: border(),
          enabledBorder: border(),
          focusedBorder: border(),
        ),
      ),
    );
  }
}
