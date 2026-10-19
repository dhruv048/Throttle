import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:throttle/models/models.dart';
import 'package:throttle/screens/auth/onboarding_screen.dart';

import 'support/fake_supabase.dart';
import 'support/providers.dart';

late FakeSupabase backend;

void main() {
  setUpAll(() async {
    backend = await FakeSupabase.start(userId: 'me');
  });

  setUp(() {
    backend.reset();
    backend.tables
      ..['profiles'] = [
        {...Fixtures.profile(), 'onboarding_completed': false},
      ]
      ..['bikes'] = [];
  });

  testWidgets(
      'names start with a capital, and the keyboard closes on the way to Home',
      (tester) async {
    Profile? done;
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(withProviders(MaterialApp(
      home: OnboardingScreen(
        initialUsername: 'priya_g',
        onCompleted: (p) => done = p,
      ),
    )));

    // Username, city, first motorcycle, year.
    final city = find.byType(TextField).at(1);
    final bike = find.byType(TextField).at(2);
    expect(find.widgetWithText(TextField, 'Kathmandu'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Yamaha MT-15'), findsOneWidget);
    await tester.enterText(city, 'bhaktapur');
    await tester.enterText(bike, 'yamaha mt-15');
    await tester.pump();
    expect(find.text('Bhaktapur'), findsOneWidget);
    expect(find.text('Yamaha mt-15'), findsOneWidget);
    expect(tester.widget<TextField>(bike).textCapitalization,
        TextCapitalization.words);
    expect(tester.testTextInput.isVisible, isTrue);

    await tester.ensureVisible(find.text('LET’S RIDE', skipOffstage: false));
    await tester.pump();
    await tester.tap(find.text('LET’S RIDE'));
    await tester.pump();
    expect(tester.testTextInput.isVisible, isFalse);
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(done, isNotNull);
    expect(backend.tables['bikes']!.single['name'], 'Yamaha mt-15');
    expect(backend.tables['profiles']!.single['city'], 'Bhaktapur');
    expect(FocusManager.instance.primaryFocus?.context?.widget,
        isNot(isA<EditableText>()));
  });
}
