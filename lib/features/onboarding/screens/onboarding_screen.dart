import 'package:travibe/core/theme/action_button_style.dart';
import 'package:flutter/material.dart';
import 'package:slider_button/slider_button.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';
import 'package:travibe/core/constants/app_sizes.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:go_router/go_router.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/routing/app_routes.dart';
import 'package:travibe/core/widgets/error_retry_view.dart';
import 'package:travibe/core/widgets/travibe_loading_indicator.dart';
import 'package:travibe/features/auth/screens/sign_up_screen.dart';
import 'package:travibe/features/onboarding/data/onboarding_repo.dart';
import 'package:travibe/features/onboarding/data/models/onboarding_model.dart';
import 'package:travibe/features/onboarding/widgets/language_button.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, this.repo});
  final OnboardingRepo? repo;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController pageController = PageController();
  int currentPage = 0;
  late final OnboardingRepo _repo = widget.repo ?? OnboardingRepo.shared;
  late Future<List<OnboardingModel>> _slides;
  bool _finishing = false;

  bool get _arabic => PreferencesManager().getLanguage() == 'ar';

  @override
  void initState() {
    super.initState();
    _slides = _repo.slides(PreferencesManager().getLanguage());
  }

  void _reload() {
    setState(() {
      currentPage = 0;
      if (pageController.hasClients) pageController.jumpToPage(0);
      _slides = _repo.slides(PreferencesManager().getLanguage());
    });
  }

  Future<bool> _finish() async {
    if (_finishing) return false;
    setState(() => _finishing = true);
    try {
      await PreferencesManager().completeOnboarding();
      if (!mounted) return false;
      final router = GoRouter.maybeOf(context);
      if (router != null) {
        router.go(AppRoutes.register);
      } else {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(builder: (_) => const SignUpScreen()),
        );
      }
      return true;
    } catch (_) {
      if (mounted) {
        setState(() => _finishing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _arabic
                  ? 'تعذر حفظ اختيارك. حاول مرة أخرى.'
                  : 'Unable to save your choice. Please retry.',
            ),
          ),
        );
      }
      return false;
    }
  }

  Widget _artwork(OnboardingModel model) {
    Widget local() => model.localImage == null
        ? const SizedBox.expand()
        : Image.asset(
            model.localImage!,
            width: double.infinity,
            fit: BoxFit.cover,
          );
    if (model.assetUrl == null) return local();
    return Image.network(
      model.assetUrl!,
      width: double.infinity,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => local(),
    );
  }

  @override
  void dispose() {
    pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Scaffold(
        appBar: AppBar(
          actions: [LanguageButton(repo: _repo, onChanged: _reload)],
        ),
        body: FutureBuilder<List<OnboardingModel>>(
          future: _slides,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: TravibeLoadingIndicator());
            }
            if (snapshot.hasError || !snapshot.hasData) {
              return Column(
                children: [
                  Expanded(
                    child: ErrorRetryView(
                      message: _arabic
                          ? 'تعذر تحميل المقدمة.'
                          : 'Unable to load onboarding.',
                      onRetry: _reload,
                    ),
                  ),
                  TextButton(
                    onPressed: _finishing ? null : _finish,
                    child: Text(_arabic ? 'تخطي' : 'Skip'),
                  ),
                ],
              );
            }
            final slides = snapshot.data!;
            return PageView.builder(
              controller: pageController,
              onPageChanged: (index) {
                setState(() {
                  currentPage = index;
                });
              },
              itemCount: slides.length,

              itemBuilder: (context, index) {
                final OnboardingModel model = slides[index];
                return SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(height: AppSizes.h369, child: _artwork(model)),
                      SizedBox(height: AppSizes.h20),
                      Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: AppSizes.ph20,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SmoothPageIndicator(
                              controller: pageController, // PageController
                              count: slides.length,
                              effect: ExpandingDotsEffect(
                                dotHeight: 8,
                                dotWidth: 8,
                                activeDotColor: DarkColors.primaryColor,
                                dotColor: Color(0xFF303030),
                              ),
                            ),
                            SizedBox(height: AppSizes.h35),
                            Text(
                              model.title,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: AppSizes.sp32,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            SizedBox(height: AppSizes.h16),
                            Text(
                              model.description,
                              style: TextStyle(
                                color: Color(0xFFD3D1CF),
                                fontSize: AppSizes.sp16,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                            SizedBox(height: AppSizes.h52),
                            if (currentPage == slides.length - 1)
                              Stack(
                                alignment: Alignment.center,
                                children: [
                                  SliderButton(
                                    width: double.infinity,
                                    height: AppSizes.h62,
                                    buttonSize: AppSizes.w54,

                                    backgroundColor: const Color(0xFF151515),
                                    buttonColor: DarkColors.primaryColor,

                                    shimmer: false,

                                    alignLabel: Alignment.center,

                                    label: Text(
                                      _arabic ? 'ابدأ الآن' : 'Get Started',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: AppSizes.sp20,
                                        fontWeight: FontWeight.w400,
                                      ),
                                    ),

                                    // This is the draggable orange circle
                                    icon: const Icon(
                                      Icons.arrow_forward_ios,
                                      color: Colors.white,
                                      size: 18,
                                    ),

                                    action: _finish,
                                  ),

                                  // Fixed arrows on the right
                                  Positioned(
                                    right: 18,
                                    child: IgnorePointer(
                                      child: Icon(
                                        Icons.keyboard_double_arrow_right,
                                        color: Colors.white,
                                        size: AppSizes.sp16,
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            else
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  TextButton(
                                    onPressed: _finishing ? null : _finish,
                                    child: Padding(
                                      padding: EdgeInsets.only(
                                        left: AppSizes.w32,
                                      ),
                                      child: Text(
                                        _arabic ? 'تخطي' : 'Skip',
                                        style: TextStyle(
                                          color: Color(0xFFD3D1CF),
                                          fontSize: AppSizes.sp16,
                                          fontWeight: FontWeight.w400,
                                        ),
                                      ),
                                    ),
                                  ),
                                  SizedBox(
                                    width: 160,
                                    height: 48,
                                    child: ElevatedButton(
                                      onPressed: () {
                                        if (currentPage < slides.length - 1) {
                                          pageController.nextPage(
                                            duration: Duration(
                                              milliseconds: 300,
                                            ),
                                            curve: Curves.easeInOut,
                                          );
                                        } else {
                                          // Navigate to the next screen or perform any action when onboarding is complete
                                        }
                                      },
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor:
                                            DarkColors.primaryColor,
                                        foregroundColor: Colors.white,
                                        elevation: 0,
                                        padding: EdgeInsets.zero,
                                        shape: ActionButtonStyle.shape,
                                      ),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Text(
                                            _arabic ? 'التالي' : 'Next',
                                            style: TextStyle(
                                              fontSize:
                                                  ActionButtonStyle.fontSize,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                          SizedBox(width: 12),
                                          Icon(
                                            Icons.arrow_forward_ios,
                                            size: AppSizes.sp16,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
