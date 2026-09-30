import 'package:flutter_test/flutter_test.dart';
import 'package:throttle/main.dart';

void main() {
  testWidgets('Throttle home greeting loads', (tester) async {
    await tester.pumpWidget(const ThrottleApp());
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.textContaining('Morning,'), findsOneWidget);
    expect(find.text('Start Ride'), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
  });
}
