import 'package:flutter/material.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:travibe/core/widgets/sheet_handle.dart';
import 'package:travibe/features/stories/data/story_audience.dart';

/// Uses existing Travibe sheet styling pending the current audience reference.
Future<StoryAudience?> showStoryAudienceSheet(
  BuildContext context, {
  required StoryAudience selected,
}) => showModalBottomSheet<StoryAudience>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: DarkColors.backgroundColor,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
  ),
  builder: (context) => SafeArea(
    top: false,
    child: SingleChildScrollView(
      key: const ValueKey('story-audience-sheet'),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Center(child: SheetHandle()),
          const SizedBox(height: 24),
          const Text(
            'Story audience',
            style: TextStyle(
              fontFamily: 'Plus Jakarta Sans',
              fontSize: 18,
              fontWeight: FontWeight.w600,
              letterSpacing: 0,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 16),
          for (final audience in StoryAudience.values)
            Semantics(
              selected: audience == selected,
              child: ListTile(
                key: ValueKey('story-audience-option-${audience.name}'),
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  audience == StoryAudience.public
                      ? Icons.language
                      : Icons.people_outline,
                  color: Colors.white,
                ),
                title: Text(
                  audience.label,
                  style: const TextStyle(
                    fontFamily: 'Plus Jakarta Sans',
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: Colors.white,
                    letterSpacing: 0,
                  ),
                ),
                subtitle: Text(
                  audience.description,
                  style: const TextStyle(
                    fontFamily: 'Plus Jakarta Sans',
                    fontSize: 12,
                    color: DarkColors.greyColor,
                  ),
                ),
                trailing: Icon(
                  audience == selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  color: audience == selected
                      ? DarkColors.primaryColor
                      : DarkColors.greyColor,
                ),
                onTap: () => Navigator.pop(context, audience),
              ),
            ),
        ],
      ),
    ),
  ),
);
