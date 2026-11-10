import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/features/block/cubit/block_cubit.dart';
import 'package:travibe/features/follow/cubit/follow_cubit.dart';
import 'package:travibe/features/profile/cubit/current_user_cubit.dart';

/// Keep Root's relationship and identity owners when opening Navigator routes.
/// Providers are borrowed; the route never disposes or duplicates them.
Widget chatRouteScope(BuildContext context, Widget child) {
  final follow = context.read<FollowCubit?>();
  final block = context.read<BlockCubit?>();
  final current = context.read<CurrentUserCubit?>();
  if (follow == null && block == null && current == null) return child;
  return MultiBlocProvider(
    providers: [
      if (follow != null) BlocProvider.value(value: follow),
      if (block != null) BlocProvider.value(value: block),
      if (current != null) BlocProvider.value(value: current),
    ],
    child: child,
  );
}
