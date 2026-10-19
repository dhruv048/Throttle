import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:throttle/main.dart';

import 'support/providers.dart';

void main() {
  testWidgets('Throttle home greeting loads', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532); // a phone
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(withProviders(const ThrottleApp(home: Shell())));
    await tester.pump(const Duration(milliseconds: 600));
    // No signed-in rider here, so the greeting has no name.
    expect(
        find.textContaining(RegExp('Morning|Afternoon|Evening')), findsWidgets);
    expect(find.text('Start Ride'), findsOneWidget);
    expect(find.text('HOME'), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
  });
}
