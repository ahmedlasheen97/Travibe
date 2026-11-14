import 'package:travibe/core/widgets/glass_surface.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:travibe/core/constants/app_sizes.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/features/block/cubit/block_cubit.dart';
import 'package:travibe/features/follow/cubit/follow_cubit.dart';
import 'package:travibe/features/follow_requests/cubit/incoming_requests_cubit.dart';
import 'package:flutter/material.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:travibe/features/profile/screens/settings_screen.dart';

class ProfileTopBar extends StatelessWidget {
  const ProfileTopBar({super.key});

  @override
  Widget build(BuildContext context) {
    final block = context.read<BlockCubit?>();
    final follow = context.read<FollowCubit?>();
    final incoming = context.read<IncomingRequestsCubit?>();
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: AppSizes.pw20),
      child: SizedBox(
        height: AppSizes.h44,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Text(
              'My Profile',
              style: TextStyle(
                color: DarkColors.whiteColor,
                fontSize: AppSizes.sp16,
                fontWeight: FontWeight.w600,
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              // Same 44×44 glass circle and 24 white icon as the header's
              // Back / ⋮ buttons.
              child: IconButton(
                key: const ValueKey('profile-settings'),
                tooltip: 'Settings',
                iconSize: AppSizes.w44,
                style: IconButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.square(AppSizes.w44),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: const CircleBorder(),
                ),
                onPressed: block == null
                    ? null
                    : () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => MultiBlocProvider(
                            providers: [
                              BlocProvider.value(value: block),
                              if (follow != null)
                                BlocProvider.value(value: follow),
                              if (incoming != null)
                                BlocProvider.value(value: incoming),
                            ],
                            child: const SettingsScreen(),
                          ),
                        ),
                      ),
                icon: GlassSurface(
                  radius: 999,
                  opacity: .65,
                  child: SizedBox.square(
                    dimension: AppSizes.w44,
                    child: Center(
                      child: SvgPicture.asset(
                        'assets/images/icons/setting-2.svg',
                        width: AppSizes.w24,
                        height: AppSizes.w24,
                        colorFilter: const ColorFilter.mode(
                          DarkColors.whiteColor,
                          BlendMode.srcIn,
                        ),
                        excludeFromSemantics: true,
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
