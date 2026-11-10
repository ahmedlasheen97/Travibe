import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/models/public_user_model.dart';
import 'package:travibe/features/follow/cubit/follow_cubit.dart';
import 'package:travibe/features/follow/data/follow_repo.dart';
import 'package:travibe/features/follow/widgets/follow_action_builder.dart';

class ButtonRepo extends FollowRepo {
  final result = Completer<PublicUserModel>();
  int calls = 0;
  @override
  Future<PublicUserModel> setFollowing(String id, bool following) {
    calls++;
    return result.future;
  }
}

Widget buttons(FollowCubit cubit) => MaterialApp(
  home: BlocProvider.value(
    value: cubit,
    child: Scaffold(
      body: Column(
        children: [
          for (var i = 0; i < 2; i++)
            FollowActionBuilder(
              userId: '7',
              initialFollowing: false,
              builder: (context, following, pending, onToggle) => TextButton(
                onPressed: onToggle,
                child: Text(
                  pending
                      ? 'Updating'
                      : following
                      ? 'Following'
                      : 'Follow',
                ),
              ),
            ),
        ],
      ),
    ),
  ),
);
void main() {
  testWidgets(
    'two occurrences share pending/confirmed state and disable duplicates',
    (tester) async {
      final repo = ButtonRepo();
      final cubit = FollowCubit(repo: repo);
      addTearDown(cubit.close);
      await tester.pumpWidget(buttons(cubit));
      expect(find.text('Follow'), findsNWidgets(2));
      await tester.tap(find.text('Follow').first);
      await tester.pump();
      expect(find.text('Updating'), findsNWidgets(2));
      for (final button in tester.widgetList<TextButton>(
        find.byType(TextButton),
      )) {
        expect(button.onPressed, isNull);
      }
      expect(repo.calls, 1);
      repo.result.complete(
        PublicUserModel.fromJson({'id': 7, 'is_following': 'true'}),
      );
      await tester.pump();
      expect(find.text('Following'), findsNWidgets(2));
    },
  );
  testWidgets(
    'backend error is shown once and shared confirmed state stays unchanged',
    (tester) async {
      final repo = ButtonRepo();
      final cubit = FollowCubit(repo: repo);
      addTearDown(cubit.close);
      await tester.pumpWidget(buttons(cubit));
      await tester.tap(find.text('Follow').first);
      await tester.pump();
      repo.result.completeError(
        ApiError(message: 'Cannot follow this user', statusCode: 422),
      );
      await tester.pump();
      expect(find.text('Follow'), findsNWidgets(2));
      expect(find.text('Cannot follow this user'), findsOneWidget);
    },
  );
}
