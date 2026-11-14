import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:travibe/core/constants/app_sizes.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:travibe/core/widgets/options_sheet.dart';
import 'package:travibe/core/widgets/travibe_toast.dart';
import 'package:travibe/features/create_post/data/post_image.dart';
import 'package:travibe/features/create_post/data/post_image_picker.dart';
import 'package:travibe/features/profile/cubit/report_problem_cubit.dart';
import 'package:travibe/features/profile/data/support_repo.dart';
import 'package:travibe/features/profile/widgets/settings_form.dart';

class ReportProblemScreen extends StatefulWidget {
  const ReportProblemScreen({super.key, this.repo, this.picker});

  final SupportRepo? repo;
  final PostImagePicker? picker;

  @override
  State<ReportProblemScreen> createState() => _ReportProblemScreenState();
}

class _ReportProblemScreenState extends State<ReportProblemScreen> {
  final _description = TextEditingController();
  late final _cubit = ReportProblemCubit(repo: widget.repo);
  late final _picker = widget.picker ?? PostImagePicker();
  final _screenshots = <PostImage>[];
  ProblemCategory? _category;
  bool _picking = false;

  bool get _canSubmit =>
      _category != null && _description.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _description.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _description.dispose();
    _cubit.close();
    super.dispose();
  }

  Future<void> _chooseCategory() async {
    FocusScope.of(context).unfocus();
    final picked = await showOptionsSheet<ProblemCategory>(
      context,
      builder: (sheet) => OptionsSheetBody(
        children: [
          for (final category in SupportRepo.categories)
            OptionSheetTile(
              key: ValueKey('problem-category-${category.slug}'),
              icon: Icon(
                category == _category
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: category == _category
                    ? DarkColors.primaryColor
                    : Colors.white54,
              ),
              label: category.label,
              onTap: () => Navigator.pop(sheet, category),
            ),
        ],
      ),
    );
    if (picked != null && mounted) setState(() => _category = picked);
  }

  Future<void> _addScreenshots() async {
    final remaining = SupportRepo.maxScreenshots - _screenshots.length;
    if (_picking || remaining < 1) return;
    _picking = true;
    final toast = TravibeToast.of(context);
    try {
      final pick = await _picker.pickGallery(limit: remaining);
      if (!mounted) return;
      final added = pick.images.take(remaining).toList();
      setState(() => _screenshots.addAll(added));
      if (pick.rejected > 0 || pick.images.length > added.length) {
        toast.present(
          TravibeToastData.error(
            pick.rejected > 0
                ? 'Some photos were skipped. Use JPEG, PNG, GIF or WebP up to 20 MB.'
                : 'You can add up to ${SupportRepo.maxScreenshots} screenshots.',
          ),
        );
      }
    } on PostImagePermissionDenied {
      toast.present(
        const TravibeToastData.error('Allow photo access to add a screenshot.'),
      );
    } catch (_) {
      toast.present(
        const TravibeToastData.error('Unable to open your photos.'),
      );
    } finally {
      _picking = false;
    }
  }

  void _submit() {
    final category = _category;
    if (category == null || !_canSubmit) return;
    FocusScope.of(context).unfocus();
    _cubit.submit(
      category: category.slug,
      description: _description.text,
      screenshots: List.of(_screenshots),
    );
  }

  @override
  Widget build(BuildContext context) =>
      BlocConsumer<ReportProblemCubit, ReportProblemState>(
        bloc: _cubit,
        listener: (context, state) {
          if (state.sent) {
            final toast = TravibeToast.of(context);
            Navigator.of(context).pop();
            toast.present(
              const TravibeToastData.success('Thanks, we received your report'),
            );
          } else if (state.error case final message?) {
            TravibeToast.show(context, TravibeToastData.error(message));
          }
        },
        builder: (context, state) {
          final busy = state.submitting || state.sent;
          return SettingsFormScaffold(
            title: 'Report a Problem',
            busy: busy,
            button: SettingsActionButton(
              key: const ValueKey('submit-report'),
              label: 'Submit Report',
              loading: busy,
              loadingLabel: 'Sending report',
              onPressed: _canSubmit ? _submit : null,
            ),
            children: [
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: _CategoryPill(
                  label: _category?.label,
                  onTap: busy ? null : _chooseCategory,
                ),
              ),
              SizedBox(height: AppSizes.adaptiveHeight(28)),
              const SettingsFieldLabel('Problem', required: true),
              SettingsMultilineField(
                fieldKey: const ValueKey('problem-description'),
                controller: _description,
                hintText: 'Describe your problem',
                maxLength: SupportRepo.maxDescription,
                enabled: !busy,
              ),
              SizedBox(height: AppSizes.h24),
              Text.rich(
                TextSpan(
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: AppSizes.sp16,
                  ),
                  children: [
                    const TextSpan(text: 'Add Screenshot '),
                    TextSpan(
                      text: '(optional)',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .55),
                        fontSize: AppSizes.sp14,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: AppSizes.h12),
              Wrap(
                spacing: AppSizes.adaptiveWidth(12),
                runSpacing: AppSizes.adaptiveHeight(12),
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (final shot in _screenshots)
                    _Thumbnail(
                      key: ValueKey('screenshot-${shot.localId}'),
                      image: shot,
                      onRemove: busy
                          ? null
                          : () => setState(() => _screenshots.remove(shot)),
                    ),
                  if (_screenshots.length < SupportRepo.maxScreenshots)
                    IconButton(
                      key: const ValueKey('add-screenshot'),
                      tooltip: 'Add screenshot',
                      onPressed: busy ? null : _addScreenshots,
                      style: IconButton.styleFrom(
                        minimumSize: const Size.square(44),
                      ),
                      icon: SvgPicture.asset(
                        'assets/images/icons/gallery-add.svg',
                        width: 28,
                        height: 28,
                        colorFilter: const ColorFilter.mode(
                          Colors.white70,
                          BlendMode.srcIn,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      );
}

class _CategoryPill extends StatelessWidget {
  const _CategoryPill({required this.label, required this.onTap});
  final String? label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(999);
    return Material(
      color: settingsFieldFill,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: const BorderSide(color: settingsFieldBorder),
      ),
      child: InkWell(
        key: const ValueKey('problem-category'),
        borderRadius: radius,
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: AppSizes.adaptiveWidth(20),
            vertical: AppSizes.adaptiveHeight(14),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  label ?? 'Problem category',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: label == null
                        ? Colors.white.withValues(alpha: .7)
                        : Colors.white,
                    fontSize: AppSizes.sp16,
                  ),
                ),
              ),
              SizedBox(width: AppSizes.adaptiveWidth(24)),
              const Icon(
                Icons.keyboard_arrow_down_rounded,
                color: Colors.white,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({super.key, required this.image, required this.onRemove});
  final PostImage image;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final size = AppSizes.adaptiveRadius(72);
    return SizedBox.square(
      dimension: size + 8,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            bottom: 0,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppSizes.adaptiveRadius(12)),
              child: Image.memory(
                image.bytes,
                width: size,
                height: size,
                fit: BoxFit.cover,
                gaplessPlayback: true,
              ),
            ),
          ),
          Positioned(
            top: 0,
            right: 0,
            child: Semantics(
              button: true,
              label: 'Remove screenshot',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onRemove,
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white24),
                  ),
                  child: const Icon(
                    Icons.close_rounded,
                    size: 14,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
