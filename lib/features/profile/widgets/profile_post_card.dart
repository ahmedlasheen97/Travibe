import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:travibe/core/constants/app_sizes.dart';
import 'package:travibe/core/theme/dark_colors.dart';

class ProfilePostCard extends StatelessWidget {
  final String name;
  final String avatar;
  final String time;
  final String text;
  final String? location;
  final String? image;
  final String likes;
  final String comments;
  final String shares;

  const ProfilePostCard({
    super.key,
    required this.name,
    required this.avatar,
    required this.time,
    required this.text,
    this.location,
    this.image,
    required this.likes,
    required this.comments,
    required this.shares,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF141414),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(radius: 20, backgroundImage: AssetImage(avatar)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      time,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: AppSizes.w38,
                height: AppSizes.h38,
                // padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFF2E2E2E)),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Center(
                  child: Icon(Icons.more_vert, color: DarkColors.whiteColor),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              height: 1.4,
            ),
          ),
          if (location != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.location_on_outlined,
                    color: Colors.white70,
                    size: 14,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    location!,
                    style: const TextStyle(
                      color: DarkColors.whiteColor,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (image != null) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.asset(
                image!,
                height: 220,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              _actionIcon('assets/images/interactions/heart.svg', likes),
              SizedBox(width: AppSizes.w8),
              _actionIcon('assets/images/interactions/message.svg', comments),
              SizedBox(width: AppSizes.w8),
              _actionIcon('assets/images/interactions/send-2.svg', shares),
              const Spacer(),
              SvgPicture.asset(
                'assets/images/interactions/archive 2.svg',
                width: 20,
                height: 20,
                colorFilter: const ColorFilter.mode(
                  DarkColors.whiteColor,
                  BlendMode.srcIn,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _actionIcon(String iconPath, String count) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: AppSizes.pw8,
        vertical: AppSizes.ph6,
      ),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFF2E2E2E)),
        borderRadius: BorderRadius.circular(AppSizes.r24),
      ),
      child: Row(
        children: [
          SvgPicture.asset(
            iconPath,
            width: 18,
            height: 18,
            colorFilter: const ColorFilter.mode(
              DarkColors.whiteColor,
              BlendMode.srcIn,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            count,
            style: const TextStyle(color: DarkColors.whiteColor, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
