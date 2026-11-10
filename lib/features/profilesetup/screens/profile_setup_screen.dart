import 'package:travibe/core/widgets/back_button_widget.dart';
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

class ProfileSetupScreen extends StatelessWidget {
  const ProfileSetupScreen({super.key});

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
          ProfileSetupCubit(currentUser: context.read<CurrentUserCubit?>())
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
            canPop: state.step == 0,
            onPopInvokedWithResult: (didPop, result) {
              if (!didPop) cubit.goBack();
            },
            child: SafeArea(
              child: Scaffold(
                appBar: AppBar(
                  elevation: 0,
                  centerTitle: true,
                  leading: BackButtonWidget(
                    onTap: () {
                      if (!cubit.goBack()) Navigator.of(context).maybePop();
                    },
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
                          Step1BasicInfo(
                            fullNameController: cubit.fullNameController,
                            usernameController: cubit.usernameController,
                            usernameStatus: state.usernameStatus,
                            usernameMessage: state.usernameMessage,
                            onUsernameChanged: cubit.onUsernameChanged,
                            avatarFile: state.avatarFile,
                            onAvatarPicked: cubit.setAvatar,
                            currentLocation:
                                state.currentLocation ??
                                context
                                    .read<CurrentUserCubit?>()
                                    ?.state
                                    .profile
                                    ?.currentLocation,
                            onCityChanged: cubit.setCity,
                            isSaving: state.isSaving,
                            onNext: cubit.saveBasicInfo,
                            onSkip: () => _goHome(context),
                          ),
                          Step2LanguagesInterests(
                            selectedLanguages: state.languages,
                            onLanguagesChanged: cubit.setLanguages,
                            selectedInterests: state.interests,
                            onInterestsChanged: cubit.setInterests,
                            isSaving: state.isSaving,
                            onNext: cubit.saveLanguagesAndInterests,
                            onSkip: () => _goHome(context),
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
