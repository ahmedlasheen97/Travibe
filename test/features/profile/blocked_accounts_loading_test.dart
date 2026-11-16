import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:travibe/features/block/cubit/block_cubit.dart';
import 'package:travibe/features/follow/cubit/follow_cubit.dart';
import 'package:travibe/features/follow/cubit/follow_users_cubit.dart';
import 'package:travibe/features/follow/widgets/people_skeleton.dart';
import 'package:travibe/features/profile/screens/blocked_account_screen.dart';
import '../block/blocked_users_test.dart' show ListRepo, page;

void main() {
  testWidgets(
    'blocked accounts: skeleton on first load, no loading line on refresh',
    (tester) async {
      final repo = ListRepo();
      final follow = FollowCubit();
      final block = BlockCubit(repo: repo, follow: follow);
      addTearDown(block.close);
      addTearDown(follow.close);
      await tester.pumpWidget(
        ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (_, _) => MultiBlocProvider(
            providers: [
              BlocProvider.value(value: follow),
              BlocProvider.value(value: block),
            ],
            child: const MaterialApp(home: BlockedAccountsScreen()),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(PeopleSkeleton), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      repo.requests.last.result.complete(page(1, [7], last: 1));
      await tester.pumpAndSettle();
      expect(find.byType(PeopleSkeleton), findsNothing);
      expect(find.text('No blocked accounts'), findsNothing);

      final list = tester
          .element(find.byType(CustomScrollView))
          .read<FollowUsersCubit>();
      final refresh = list.load(force: true);
      await tester.pump();
      expect(list.state.refreshing, isTrue);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.byType(PeopleSkeleton), findsNothing);

      repo.requests.last.result.complete(page(1, [7], last: 1));
      await refresh;
      await tester.pumpAndSettle();
    },
  );
}
