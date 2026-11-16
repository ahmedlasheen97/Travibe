import 'package:travibe/core/widgets/back_button_widget.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:flutter/material.dart';
import 'package:travibe/features/profile/cubit/current_user_cubit.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';
import 'package:travibe/core/constants/app_sizes.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:travibe/features/profilesetup/cubit/profile_setup_cubit.dart';
import 'package:travibe/features/profilesetup/data/reference_item.dart';
import 'package:travibe/features/profilesetup/widgets/step1_basic_info.dart';
import 'package:travibe/features/profilesetup/widgets/step2_languages_interests.dart';
import 'package:travibe/features/profilesetup/widgets/step3_travel_style.dart';
import 'package:travibe/root.dart';

class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({super.key, this.createCubit});
  final ProfileSetupCubit Function(BuildContext)? createCubit;
  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  bool _backDialogOpen = false;
  Future<void> _back(BuildContext context, ProfileSetupCubit cubit) async {
    if (_backDialogOpen) return;
    if (cubit.goBack()) return;
    if (cubit.state.avatar != null ||
        cubit.state.selectingAvatar ||
        cubit.state.uploadingAvatar) {
      _backDialogOpen = true;
      final session = PreferencesManager().sessionRevision;
      final leave = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Leave without saving photo?'),
          content: const Text(
            'Your selected photo has not been confirmed as saved. Leaving cancels the pending upload.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Stay'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Leave'),
            ),
          ],
        ),
      );
      _backDialogOpen = false;
      if (!context.mounted ||
          leave != true ||
          cubit.isClosed ||
          session != PreferencesManager().sessionRevision) {
        return;
      }
      cubit.discardAvatar();
      Navigator.of(context).pop();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  static const int _totalSteps = 3;

  void _goHome(BuildContext context) {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => Root()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<ProfileSetupCubit>(
      create: (context) =>
          (widget.createCubit?.call(context) ??
                ProfileSetupCubit(
                  currentUser: context.read<CurrentUserCubit?>(),
                ))
            ..restore()
            ..loadCatalogs(),
      child: BlocConsumer<ProfileSetupCubit, ProfileSetupState>(
        listenWhen: (previous, current) => previous.status != current.status,
        listener: (context, state) {
          if (state.status == ProfileSetupStatus.completed) {
            _goHome(context);
          } else if (state.status == ProfileSetupStatus.failure) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(state.errorMessage)));
          }
        },
        builder: (context, state) {
          final cubit = context.read<ProfileSetupCubit>();

          return PopScope(
            canPop:
                state.step == 0 &&
                state.avatar == null &&
                !state.selectingAvatar &&
                !state.uploadingAvatar,
            onPopInvokedWithResult: (didPop, result) {
              if (!didPop) _back(context, cubit);
            },
            child: SafeArea(
              child: Scaffold(
                backgroundColor: DarkColors.backgroundColor,
                appBar: AppBar(
                  backgroundColor: DarkColors.backgroundColor,
                  surfaceTintColor: Colors.transparent,
                  scrolledUnderElevation: 0,
                  elevation: 0,
                  centerTitle: true,
                  leading: BackButtonWidget(
                    onTap: () => _back(context, cubit),
                    size: 44,
                    iconSize: 18,
                  ),
                  title: const Text(
                    'Profile Setup',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                body: Column(
                  children: [
                    const SizedBox(height: 12),
                    SmoothPageIndicator(
                      controller: cubit.pageController,
                      count: _totalSteps,
                      effect: const ExpandingDotsEffect(
                        dotHeight: 8,
                        dotWidth: 8,
                        activeDotColor: DarkColors.primaryColor,
                        dotColor: Color(0xFF303030),
                      ),
                    ),
                    SizedBox(height: AppSizes.h12),
                    Expanded(
                      child: PageView(
                        controller: cubit.pageController,
                        physics: const NeverScrollableScrollPhysics(),
                        onPageChanged: cubit.onPageChanged,
                        children: [
                          Step1BasicInfo(cubit: cubit),
                          Step2LanguagesInterests(
                            selectedLanguages: state.languages,
                            onLanguagesChanged: cubit.setLanguages,
                            selectedInterests: state.interests,
                            onInterestsChanged: cubit.setInterests,
                            isSaving: state.isSaving,
                            onNext: cubit.saveLanguagesAndInterests,
                          ),
                          Step3TravelStyle(
                            catalog: state.catalog(ReferenceKind.travelStyles),
                            onRetry: () =>
                                cubit.loadCatalog(ReferenceKind.travelStyles),
                            selectedTravelStyles: state.travelStyles,
                            onTravelStylesChanged: cubit.setTravelStyles,
                            onFinish: state.isSaving ? null : cubit.finish,
                            isSubmitting: state.isSaving,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
