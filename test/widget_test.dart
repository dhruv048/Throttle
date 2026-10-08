import 'package:flutter_test/flutter_test.dart';
import 'package:throttle/main.dart';

void main() {
  testWidgets('Throttle home greeting loads', (tester) async {
    await tester.pumpWidget(const ThrottleApp(home: Shell()));
    await tester.pump(const Duration(milliseconds: 600));
    // No signed-in rider here, so the greeting has no name.
    expect(find.textContaining(RegExp('Morning|Afternoon|Evening')), findsWidgets);
    expect(find.text('Start Ride'), findsOneWidget);
    expect(find.text('HOME'), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
  });
}
