import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:travibe/core/widgets/travibe_choice_chip.dart';
import 'package:travibe/features/profile/data/profile_model.dart';
import 'package:travibe/features/profile/screens/interests_screen.dart';
import 'package:travibe/features/profile/screens/languages_screen.dart';

const _options = [
  ProfileReference(slug: 'english', name: 'English'),
  ProfileReference(slug: 'arabic', name: 'Arabic'),
];

BoxDecoration _decoration(WidgetTester tester, String label) =>
    tester
            .widget<Container>(
              find
                  .descendant(
                    of: find.widgetWithText(TravibeChoiceChip, label),
                    matching: find.byType(Container),
                  )
                  .first,
            )
            .decoration!
        as BoxDecoration;

void main() {
  testWidgets('dark with grey border and white text; orange when selected', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Row(
          children: [
            TravibeChoiceChip(label: 'Off', selected: false),
            TravibeChoiceChip(label: 'On', selected: true),
          ],
        ),
      ),
    );
    expect(_decoration(tester, 'Off').color, TravibeChoiceChip.fill);
    expect(
      (_decoration(tester, 'Off').border! as Border).top.color,
      TravibeChoiceChip.border,
    );
    expect(_decoration(tester, 'On').color, DarkColors.primaryColor);
    for (final label in ['Off', 'On']) {
      expect(tester.widget<Text>(find.text(label)).style!.color, Colors.white);
    }
  });

  for (final entry in <String, Widget Function()>{
    'Languages': () => const LanguagesScreen(
      initiallySelected: ['english'],
      options: _options,
    ),
    'Interests': () => const InterestsScreen(
      initiallySelected: ['english'],
      options: _options,
    ),
  }.entries) {
    testWidgets('Edit Profile ${entry.key} uses the shared chip and toggles', (
      tester,
    ) async {
      await tester.pumpWidget(MaterialApp(home: entry.value()));
      expect(find.byType(TravibeChoiceChip), findsNWidgets(2));
      expect(_decoration(tester, 'English').color, DarkColors.primaryColor);
      expect(_decoration(tester, 'Arabic').color, TravibeChoiceChip.fill);
      await tester.tap(find.text('Arabic'));
      await tester.pump();
      expect(_decoration(tester, 'Arabic').color, DarkColors.primaryColor);
    });
  }
}
