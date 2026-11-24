import 'package:flutter/material.dart';
import 'package:travibe/core/constants/app_sizes.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:travibe/core/widgets/options_sheet.dart';
import 'package:travibe/core/widgets/sheet_handle.dart';
import 'package:travibe/features/stories/data/story_style.dart';

/// Settings → Story Style picker; same layout as [LanguageBottomSheet].
/// Pops with the chosen [StoryStyle].
class StoryStyleBottomSheet extends StatelessWidget {
  const StoryStyleBottomSheet({super.key, required this.selected});
  final StoryStyle selected;

  static const options = [StoryStyle.rectangle, StoryStyle.circle];

  static Future<StoryStyle?> show(BuildContext context, StoryStyle current) =>
      showOptionsSheet<StoryStyle>(
        context,
        builder: (_) => StoryStyleBottomSheet(selected: current),
      );

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(bottom: AppSizes.ph16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: AppSizes.h16),
            const SheetHandle(),
            SizedBox(height: AppSizes.h16),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: AppSizes.pw20),
              child: Row(
                children: [
                  Text(
                    'Story Style',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: AppSizes.sp17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: AppSizes.h12),
            for (final style in options) _tile(context, style),
          ],
        ),
      ),
    );
  }

  Widget _tile(BuildContext context, StoryStyle style) {
    final isSelected = style == selected;
    return Semantics(
      selected: isSelected,
      child: InkWell(
        key: ValueKey('story-style-option-${style.name}'),
        onTap: () => Navigator.pop(context, style),
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(
            horizontal: AppSizes.pw20,
            vertical: AppSizes.ph12,
          ),
          color: isSelected
              ? DarkColors.primaryColor.withValues(alpha: 0.15)
              : Colors.transparent,
          child: Row(
            children: [
              StoryStylePreview(style: style),
              SizedBox(width: AppSizes.w14),
              Expanded(
                child: Text(
                  style.label,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: AppSizes.sp15,
                  ),
                ),
              ),
              if (isSelected)
                Icon(
                  Icons.check_rounded,
                  color: DarkColors.primaryColor,
                  size: AppSizes.w20,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small outline of a story's shape: a 4:5 card (radius 1/4 width) or a
/// circle, drawn with the unseen-story orange.
class StoryStylePreview extends StatelessWidget {
  const StoryStylePreview({super.key, required this.style});
  final StoryStyle style;

  @override
  Widget build(BuildContext context) {
    final width = AppSizes.adaptiveWidth(24);
    final rectangle = style == StoryStyle.rectangle;
    return ExcludeSemantics(
      child: SizedBox(
        width: AppSizes.adaptiveWidth(28),
        height: AppSizes.adaptiveWidth(32),
        child: Center(
          child: Container(
            key: ValueKey('story-style-preview-${style.name}'),
            width: width,
            height: rectangle ? width * 1.25 : width,
            decoration: BoxDecoration(
              color: const Color(0xFF2A2A2A),
              shape: rectangle ? BoxShape.rectangle : BoxShape.circle,
              borderRadius: rectangle ? BorderRadius.circular(width / 4) : null,
              border: Border.all(color: DarkColors.primaryColor, width: 2),
            ),
          ),
        ),
      ),
    );
  }
}
