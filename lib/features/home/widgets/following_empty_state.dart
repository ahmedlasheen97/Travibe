import 'package:flutter/material.dart';
import 'package:travibe/core/widgets/custom_button.dart';

class FollowingEmptyState extends StatelessWidget {
  final VoidCallback onExplorePeople;

  const FollowingEmptyState({super.key, required this.onExplorePeople});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // SvgPicture.asset(
            //   'assets/images/home/following.svg',
            //   width: 119,
            //   height: 121,
            // ),
           Image.asset(
              'assets/images/home/image 50.png',
              width: 119,
              height: 121,
              fit: BoxFit.contain,
            ),
            const SizedBox(height: 8),
            const Text(
              "You don’t follow anyone yet.",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Plus Jakarta Sans',
                decoration: TextDecoration.none,
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Follow people to see their stories, adventures, and latest posts here.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 14,
                height: 24 / 14,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: 197,
              child: CustomButton(
                title: 'Explore People',
                onPressed: onExplorePeople,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
