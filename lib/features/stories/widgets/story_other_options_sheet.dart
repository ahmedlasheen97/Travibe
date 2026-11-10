import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/core/widgets/sheet_handle.dart';
import 'package:travibe/features/block/cubit/block_cubit.dart';
import 'package:travibe/features/block/widgets/block_user_button.dart';

class StoryOtherOptionsSheet extends StatelessWidget {
  const StoryOtherOptionsSheet({
    super.key,
    required this.userId,
    required this.name,
    this.blocks,
    required this.canAct,
  });
  final String userId, name;
  final BlockCubit? blocks;
  final bool Function() canAct;
  @override
  Widget build(BuildContext context) {
    Widget content(BlockState? state, BuildContext actionContext) => SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          const SheetHandle(),
          const SizedBox(height: 16),
          ListTile(
            key: const ValueKey('story-report'),
            enabled: false,
            leading: SvgPicture.asset(
              'assets/images/interactions/flag.svg',
              width: 24,
              height: 24,
              excludeFromSemantics: true,
            ),
            title: const Text(
              'Report',
              style: TextStyle(
                color: Colors.white,
                fontFamily: 'Plus Jakarta Sans',
              ),
            ),
            subtitle: const Text(
              'Reporting is not available yet.',
              style: TextStyle(
                color: Colors.white54,
                fontFamily: 'Plus Jakarta Sans',
              ),
            ),
          ),
          const Divider(
            height: 1,
            indent: 24,
            endIndent: 24,
            color: Colors.white12,
          ),
          ListTile(
            key: const ValueKey('story-block-user'),
            leading: state?.pending.contains(userId) == true
                ? const SizedBox.square(
                    dimension: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.red,
                    ),
                  )
                : SvgPicture.asset(
                    'assets/images/interactions/user-remove.svg',
                    width: 24,
                    height: 24,
                    excludeFromSemantics: true,
                  ),
            title: const Text(
              'Block user',
              style: TextStyle(
                color: Colors.red,
                fontFamily: 'Plus Jakarta Sans',
              ),
            ),
            enabled: blocks != null && state?.pending.contains(userId) != true,
            onTap: blocks == null || state?.pending.contains(userId) == true
                ? null
                : () async {
                    if (!canAct()) return;
                    await confirmBlockChange(
                      actionContext,
                      userId,
                      blocked: true,
                      name: name,
                    );
                    if (actionContext.mounted &&
                        blocks!.state.isBlocked(userId) &&
                        ModalRoute.of(actionContext)?.isCurrent == true) {
                      Navigator.pop(actionContext);
                    }
                  },
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
    if (blocks == null) return content(null, context);
    return BlocProvider.value(
      value: blocks!,
      child: Builder(
        builder: (context) => BlocBuilder<BlockCubit, BlockState>(
          builder: (_, state) => content(state, context),
        ),
      ),
    );
  }
}
