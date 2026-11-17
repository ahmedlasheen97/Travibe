import 'package:travibe/core/widgets/travibe_toast.dart';
import 'package:travibe/core/widgets/upload_progress_ring.dart';
import 'package:travibe/core/widgets/back_button_widget.dart';
import 'package:flutter/material.dart';
import 'package:travibe/features/profile/cubit/current_user_cubit.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/features/profilesetup/widgets/setup_step_indicator.dart';
import 'package:travibe/core/constants/app_sizes.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'dart:typed_data';
import 'package:travibe/features/profile/widgets/profile_picture_upload_toast.dart';
import 'package:travibe/features/profilesetup/cubit/profile_setup_cubit.dart';
import 'package:travibe/features/profilesetup/data/reference_item.dart';
import 'package:travibe/features/profilesetup/widgets/step1_basic_info.dart';
import 'package:travibe/features/profilesetup/widgets/step2_languages_interests.dart';
import 'package:travibe/features/profilesetup/widgets/step3_travel_style.dart';
import 'package:travibe/root.dart';

class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({
    super.key,
    this.createCubit,
    this.popOnComplete = false,
    this.initialStep = 0,
  });
  final ProfileSetupCubit Function(BuildContext)? createCubit;

  /// Opened from inside the app (Buddies "Complete Profile"): step 1 can be
  /// left with Back, and completion returns to the caller instead of
  /// replacing the stack with a new Root.
  final bool popOnComplete;

  /// Page to open on (see [ProfileSetupCubit.firstMissingStep]).
  final int initialStep;
  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  static const int _totalSteps = 3;
  Uint8List? _announcedPreview;

  bool _avatarUploadChanged(ProfileSetupState a, ProfileSetupState b) =>
      a.uploadingAvatar != b.uploadingAvatar ||
      a.avatarUploadFailed != b.avatarUploadFailed ||
      !identical(a.avatarPreview, b.avatarPreview);

  /// Same floating toast as post uploads: progress, then success or failure.
  void _onAvatarUpload(BuildContext context, ProfileSetupState state) {
    final cubit = context.read<ProfileSetupCubit>();
    final toast = TravibeToast.of(context);
    final data = profilePictureToast(
      uploading: state.uploadingAvatar,
      failed: state.avatarUploadFailed,
      // The SnackBar is built outside this provider, so bind the cubit.
      progress: BlocSelector<ProfileSetupCubit, ProfileSetupState, double>(
        bloc: cubit,
        selector: (state) => state.avatarProgress,
        builder: (_, progress) => UploadProgressRing(progress: progress),
      ),
      onRetry: cubit.uploadAvatar,
      onDiscard: cubit.discardAvatar,
    );
    final preview = state.avatarPreview;
    if (data != null) {
      toast.present(data);
    } else if (preview != null && !identical(preview, _announcedPreview)) {
      _announcedPreview = preview;
      toast.present(profilePictureUpdatedToast);
    } else {
      toast.dismiss();
    }
  }

  void _goHome(BuildContext context) {
    if (widget.popOnComplete) {
      Navigator.of(context).pop(true);
      return;
    }
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
                  initialStep: widget.initialStep,
                ))
            ..restore()
            ..loadCatalogs(),
      child: BlocListener<ProfileSetupCubit, ProfileSetupState>(
        listenWhen: _avatarUploadChanged,
        listener: _onAvatarUpload,
        child: BlocConsumer<ProfileSetupCubit, ProfileSetupState>(
          listenWhen: (previous, current) => previous.status != current.status,
          listener: (context, state) {
            if (state.status == ProfileSetupStatus.completed ||
                state.status == ProfileSetupStatus.skipped) {
              _goHome(context);
            } else if (state.status == ProfileSetupStatus.failure) {
              TravibeToast.show(
                context,
                TravibeToastData.error(state.errorMessage),
              );
            }
          },
          builder: (context, state) {
            final cubit = context.read<ProfileSetupCubit>();

            // The account already exists, so setup never pops back to Signup or
            // OTP. Back moves to the previous step; on step 1 it does nothing.
            return PopScope(
              canPop:
                  widget.popOnComplete && state.step == 0 && !state.isSaving,
              onPopInvokedWithResult: (didPop, result) {
                if (!didPop) cubit.goBack();
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
                    automaticallyImplyLeading: false,
                    leading: state.step > 0
                        ? BackButtonWidget(onTap: cubit.goBack)
                        : widget.popOnComplete
                        ? BackButtonWidget(
                            onTap: () => Navigator.of(context).maybePop(),
                          )
                        : null,
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
                      SetupStepIndicator(
                        count: _totalSteps,
                        current: state.step,
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
                              onSkip: state.isSaving ? null : cubit.skip,
                            ),
                            Step3TravelStyle(
                              catalog: state.catalog(
                                ReferenceKind.travelStyles,
                              ),
                              onRetry: () =>
                                  cubit.loadCatalog(ReferenceKind.travelStyles),
                              selectedTravelStyles: state.travelStyles,
                              onTravelStylesChanged: cubit.setTravelStyles,
                              onFinish: state.isSaving ? null : cubit.finish,
                              onSkip: state.isSaving ? null : cubit.skip,
                              finishLabel: widget.popOnComplete
                                  ? 'Done'
                                  : 'Continue to Home',
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
      ),
    );
  }
}
