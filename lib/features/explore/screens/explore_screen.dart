import 'package:flutter/material.dart';
import 'package:travibe/core/constants/app_sizes.dart';
import 'package:travibe/core/navigation/bottom_nav_visibility.dart';
import 'package:travibe/core/theme/dark_colors.dart';

/// Explore tab placeholder until destinations/hotels ship. Fits one 390×844
/// screen without scrolling (scales down on shorter ones) and mirrors in RTL.
class ExploreScreen extends StatelessWidget {
  const ExploreScreen({super.key});

  static const illustration = 'assets/images/onboarding/on2.png';

  @override
  Widget build(BuildContext context) {
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    final navInset = BottomNavScope.bottomInsetOf(context);
    final previews = [
      (Icons.place_outlined, ar ? 'الوجهات' : 'Destinations'),
      (Icons.hotel_outlined, ar ? 'الفنادق' : 'Hotels'),
      (Icons.flight_takeoff_rounded, ar ? 'الرحلات' : 'Trips'),
      (Icons.tour_outlined, ar ? 'مرشدون محليون' : 'Local guides'),
    ];
    return Scaffold(
      backgroundColor: DarkColors.backgroundColor,
      body: SafeArea(
        // Inside Root the content runs under the hideable bottom bar.
        bottom: navInset == 0,
        child: Column(
          children: [
            // Header in the root-tab title style; no back button. Leaves the
            // top band free for a shared glow background once one exists.
            SizedBox(
              height: AppSizes.adaptiveHeight(56),
              child: Center(
                child: Text(
                  ar ? 'استكشف' : 'Explore',
                  key: const ValueKey('explore-title'),
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: AppSizes.sp18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  AppSizes.adaptiveWidth(24),
                  0,
                  AppSizes.adaptiveWidth(24),
                  navInset + AppSizes.adaptiveHeight(16),
                ),
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: SizedBox(
                      width: AppSizes.adaptiveWidth(342),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const _FloatingIllustration(),
                          SizedBox(height: AppSizes.adaptiveHeight(32)),
                          Text(
                            ar ? 'قريبًا' : 'Coming soon',
                            key: const ValueKey('explore-coming-soon'),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: AppSizes.sp28,
                              height: 1.25,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          SizedBox(height: AppSizes.adaptiveHeight(10)),
                          Text(
                            ar
                                ? 'اكتشف الوجهات والفنادق والأماكن المخفية. نحن نبني شيئًا مميزًا من أجلك.'
                                : "Discover destinations, hotels and hidden gems. We're building something special for you.",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: DarkColors.greyColor,
                              fontSize: AppSizes.sp14,
                              height: 1.5,
                            ),
                          ),
                          SizedBox(height: AppSizes.adaptiveHeight(28)),
                          ExcludeSemantics(
                            child: Opacity(
                              opacity: 0.55,
                              child: Wrap(
                                key: const ValueKey('explore-previews'),
                                alignment: WrapAlignment.center,
                                spacing: AppSizes.adaptiveWidth(8),
                                runSpacing: AppSizes.adaptiveHeight(8),
                                children: [
                                  for (final (icon, label) in previews)
                                    _PreviewChip(icon: icon, label: label),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The map illustration inside a soft orange circle (the Complete Profile
/// card's 0x33E45C10), gently floating unless reduced motion is on.
class _FloatingIllustration extends StatefulWidget {
  const _FloatingIllustration();

  @override
  State<_FloatingIllustration> createState() => _FloatingIllustrationState();
}

class _FloatingIllustrationState extends State<_FloatingIllustration>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2800),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller
        ..stop()
        ..value = 0.5;
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final outer = AppSizes.adaptiveRadius(232);
    final inner = AppSizes.adaptiveRadius(196);
    final art = Container(
      key: const ValueKey('explore-illustration'),
      width: outer,
      height: outer,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: Color(0x33E45C10),
        shape: BoxShape.circle,
      ),
      child: ClipOval(
        // Fade the map's square edges into the orange circle.
        child: ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (rect) => const RadialGradient(
            colors: [Colors.white, Colors.white, Colors.transparent],
            stops: [0, 0.62, 1],
          ).createShader(rect),
          child: Image.asset(
            ExploreScreen.illustration,
            width: inner,
            height: inner,
            fit: BoxFit.cover,
          ),
        ),
      ),
    );
    return ExcludeSemantics(
      child: AnimatedBuilder(
        animation: _controller,
        child: art,
        builder: (context, child) {
          final t = Curves.easeInOut.transform(_controller.value);
          return Transform.translate(
            offset: Offset(0, (2 * t - 1) * AppSizes.adaptiveHeight(6)),
            child: Transform.scale(scale: 0.985 + 0.03 * t, child: child),
          );
        },
      ),
    );
  }
}

class _PreviewChip extends StatelessWidget {
  const _PreviewChip({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsetsDirectional.fromSTEB(
      AppSizes.adaptiveWidth(12),
      AppSizes.adaptiveHeight(8),
      AppSizes.adaptiveWidth(14),
      AppSizes.adaptiveHeight(8),
    ),
    decoration: BoxDecoration(
      color: const Color(0xFF1C1B1A),
      border: Border.all(color: const Color(0xFF2E2D2C)),
      borderRadius: BorderRadius.circular(AppSizes.adaptiveRadius(20)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: AppSizes.adaptiveRadius(16),
          color: DarkColors.primaryColor,
        ),
        SizedBox(width: AppSizes.adaptiveWidth(6)),
        Text(
          label,
          style: TextStyle(
            color: Colors.white,
            fontSize: AppSizes.sp13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    ),
  );
}
