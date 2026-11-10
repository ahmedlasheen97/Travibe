import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../cubit/allow_location_cubit.dart';

class BuddiesVisibilityInvitation extends StatelessWidget {
  const BuddiesVisibilityInvitation({super.key});
  @override
  Widget build(BuildContext context) {
    final cubit = context.watch<AllowLocationCubit?>();
    return _content(context, cubit);
  }

  Widget _content(BuildContext context, AllowLocationCubit? cubit) => Container(
    width: double.infinity,
    constraints: const BoxConstraints(minHeight: 164),
    decoration: BoxDecoration(
      color: const Color(0xFF6644BD),
      borderRadius: BorderRadius.circular(24),
    ),
    padding: const EdgeInsets.all(12),
    // Exact illustration export is unavailable. Preserve its space instead of
    // substituting unrelated artwork or cropping a design screenshot.
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 235),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Your Next Travel Buddy Awaits',
                style: TextStyle(
                  letterSpacing: 0,
                  color: Colors.white,
                  fontSize: 16,
                  height: 24 / 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Turn on visibility to share your current city and let other travelers discover you.',
                style: TextStyle(
                  letterSpacing: 0,
                  color: Colors.white,
                  fontSize: 12,
                  height: 16 / 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Tooltip(
          message: 'Save your current city, then enable visibility',
          child: TextButton(
            onPressed: cubit == null || cubit.state.busy ? null : cubit.allow,
            style: TextButton.styleFrom(
              disabledBackgroundColor: Colors.white,
              disabledForegroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              minimumSize: const Size(0, 36),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: const StadiumBorder(),
              textStyle: Theme.of(context).textTheme.labelLarge!.copyWith(
                letterSpacing: 0,
                fontSize: 16,
                height: 24 / 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            child: Text(
              cubit?.state.busy == true
                  ? 'Saving…'
                  : cubit?.state.locationSaved == true
                  ? 'Retry visibility'
                  : 'Allow Location',
            ),
          ),
        ),
        if (cubit?.state.openSettings == true)
          TextButton(
            onPressed: cubit!.device.openSettings,
            child: const Text('Open Settings'),
          ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline, size: 16, color: Colors.white),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                cubit?.state.error ??
                    'Your current city is saved only after you allow location. You can still search destinations manually.',
                style: TextStyle(
                  letterSpacing: 0,
                  color: Colors.white,
                  fontSize: 12,
                  height: 16 / 12,
                ),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}
