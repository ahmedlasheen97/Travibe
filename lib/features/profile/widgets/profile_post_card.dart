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
      padding: EdgeInsets.all(AppSizes.pw16),
      decoration: BoxDecoration(
        color: const Color(0xFF141414),
        borderRadius: BorderRadius.circular(AppSizes.r20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: AppSizes.r20,
                backgroundImage: AssetImage(avatar),
              ),
              SizedBox(width: AppSizes.w10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: AppSizes.sp14,
                      ),
                    ),
                    Text(
                      time,
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: AppSizes.sp12,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: AppSizes.w38,
                height: AppSizes.h38,
                // padding: EdgeInsets.all(AppSizes.pw8),
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFF2E2E2E)),
                  borderRadius: BorderRadius.circular(AppSizes.r20),
                ),
                child: const Center(
                  child: Icon(Icons.more_vert, color: DarkColors.whiteColor),
                ),
              ),
            ],
          ),
          SizedBox(height: AppSizes.h12),
          Text(
            text,
            style: TextStyle(
              color: Colors.white,
              fontSize: AppSizes.sp14,
              height: 1.4,
            ),
          ),
          if (location != null) ...[
            SizedBox(height: AppSizes.h10),
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: AppSizes.pw10,
                vertical: AppSizes.ph6,
              ),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(AppSizes.r20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.location_on_outlined,
                    color: Colors.white70,
                    size: AppSizes.w14,
                  ),
                  SizedBox(width: AppSizes.w4),
                  Text(
                    location!,
                    style: TextStyle(
                      color: DarkColors.whiteColor,
                      fontSize: AppSizes.sp12,
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (image != null) ...[
            SizedBox(height: AppSizes.h12),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppSizes.r16),
              child: Image.asset(
                image!,
                height: AppSizes.h220,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
          ],
          SizedBox(height: AppSizes.h12),
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
                width: AppSizes.w20,
                height: AppSizes.h20,
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
            width: AppSizes.w18,
            height: AppSizes.h18,
            colorFilter: const ColorFilter.mode(
              DarkColors.whiteColor,
              BlendMode.srcIn,
            ),
          ),
          SizedBox(width: AppSizes.w6),
          Text(
            count,
            style: TextStyle(
              color: DarkColors.whiteColor,
              fontSize: AppSizes.sp13,
            ),
          ),
        ],
      ),
    );
  }
}
