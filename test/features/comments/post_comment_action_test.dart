import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:travibe/core/widgets/post_card.dart';

void main() {
  testWidgets('existing post card comment count invokes the comment action', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (context, child) => MaterialApp(
          home: Scaffold(
            body: PostCard(
              name: 'Sara',
              avatar: null,
              time: 'Now',
              text: 'Post',
              likes: '1',
              comments: '7',
              shares: '0',
              onCommentsTap: () => taps++,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('7'));
    expect(taps, 1);
  });
}
