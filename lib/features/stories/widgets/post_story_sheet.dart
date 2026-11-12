import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:travibe/core/widgets/sheet_handle.dart';
import 'package:travibe/features/stories/cubit/story_picker_cubit.dart';
import 'package:travibe/features/stories/data/story_editor_draft.dart';

class PostStorySheet extends StatelessWidget {
  const PostStorySheet({super.key, required this.picker});

  final StoryPickerCubit picker;

  static Future<StoryEditorDraft?> show(
    BuildContext context,
    StoryPickerCubit picker,
  ) => showModalBottomSheet<StoryEditorDraft>(
    context: context,
    backgroundColor: DarkColors.backgroundColor,
    barrierColor: Colors.black.withValues(alpha: 0.75),
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      side: BorderSide(color: Color(0xFF292929)),
    ),
    builder: (_) => PostStorySheet(picker: picker),
  );

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<StoryPickerCubit, StoryPickerState>(
      bloc: picker,
      builder: (context, state) => SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Center(child: SheetHandle()),
              const SizedBox(height: 32),
              const Text(
                'Post a Story',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Plus Jakarta Sans',
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                key: const ValueKey('story-camera'),
                onPressed: state.busy
                    ? null
                    : () async {
                        final draft = await picker.capture();
                        if (context.mounted && draft != null) {
                          Navigator.pop(context, draft);
                        }
                      },
                style: FilledButton.styleFrom(
                  backgroundColor: DarkColors.primaryColor,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: DarkColors.primaryColor.withValues(
                    alpha: 0.55,
                  ),
                  disabledForegroundColor: Colors.white70,
                  minimumSize: const Size.fromHeight(48),
                  textStyle: const TextStyle(
                    fontFamily: 'Plus Jakarta Sans',
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0,
                  ),
                ),
                icon: state.busy && state.capturing
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : SvgPicture.asset(
                        'assets/images/interactions/camera.svg',
                        width: 24,
                        height: 24,
                      ),
                label: const Text('Take a Photo'),
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                key: const ValueKey('story-gallery'),
                onPressed: state.busy
                    ? null
                    : () async {
                        final draft = await picker.pick();
                        if (context.mounted && draft != null) {
                          Navigator.pop(context, draft);
                        }
                      },
                style: TextButton.styleFrom(
                  foregroundColor: DarkColors.primaryColor,
                  minimumSize: const Size.fromHeight(48),
                  textStyle: const TextStyle(
                    fontSize: 18,
                    fontFamily: 'Plus Jakarta Sans',
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0,
                  ),
                ),
                icon: state.busy && !state.capturing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : SvgPicture.asset(
                        'assets/images/interactions/gallery.svg',
                        width: 24,
                        height: 24,
                        colorFilter: const ColorFilter.mode(
                          DarkColors.primaryColor,
                          BlendMode.srcIn,
                        ),
                      ),
                label: const Text('Choose from Gallery'),
              ),
              if (state.error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    state.error!,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontFamily: 'Plus Jakarta Sans',
                    ),
                    semanticsLabel: state.error,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
