import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:travibe/features/home/widgets/post_options_sheet.dart';

void main() {
  testWidgets('feed options expose only the implemented hide action', (
    tester,
  ) async {
    PostOptionAction? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                selected = await PostOptionsSheet.show(
                  context,
                  actions: const {PostOptionAction.hidePost},
                );
              },
              child: const Text('Options'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Options'));
    await tester.pumpAndSettle();
    expect(find.text('Hide post'), findsOneWidget);
    expect(find.text('Block user'), findsNothing);
    expect(find.text('Report'), findsNothing);
    expect(find.text('Not interested'), findsNothing);
    await tester.tap(find.text('Hide post'));
    await tester.pumpAndSettle();
    expect(selected, PostOptionAction.hidePost);
  });
}
