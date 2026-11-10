import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/features/block/cubit/block_cubit.dart';
import 'package:flutter/material.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:travibe/features/profile/screens/settings_screen.dart';

class ProfileTopBar extends StatelessWidget {
  const ProfileTopBar({super.key});

  @override
  Widget build(BuildContext context) {
    final block = context.read<BlockCubit?>();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: SizedBox(
        height: 44,
        child: Stack(
          alignment: Alignment.center,
          children: [
            const Text(
              'My Profile',
              style: TextStyle(
                color: DarkColors.whiteColor,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                tooltip: 'Settings',
                style: IconButton.styleFrom(
                  backgroundColor: DarkColors.darkgreyColor,
                ),
                onPressed: block == null
                    ? null
                    : () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => BlocProvider.value(
                            value: block,
                            child: const SettingsScreen(),
                          ),
                        ),
                      ),
                icon: const Icon(
                  Icons.settings_outlined,
                  color: DarkColors.whiteColor,
                  size: 20,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
