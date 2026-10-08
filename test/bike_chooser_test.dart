import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:throttle/models/models.dart';
import 'package:throttle/widgets/bike_chooser.dart';

void main() {
  testWidgets('shows bikes, marks the selected one, and reports taps',
      (tester) async {
    const bikes = [
      BikeRecord(
          id: 'a',
          userId: 'u',
          name: 'Yamaha MT-15',
          riddenKm: 412.3,
          isPrimary: true),
      BikeRecord(
          id: 'b', userId: 'u', name: 'Royal Enfield Himalayan', riddenKm: 57),
    ];
    String? picked;
    var added = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: BikeChooser(
          bikes: bikes,
          selectedId: 'a',
          onSelect: (b) => picked = b.id,
          onAdd: () => added = true,
        ),
      ),
    ));

    expect(find.text('Yamaha MT-15'), findsOneWidget);
    expect(find.text('412.3 km · Primary'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsOneWidget); // only the selected bike

    await tester.tap(find.text('Royal Enfield Himalayan'));
    expect(picked, 'b');

    await tester.dragUntilVisible(
      find.text('ADD BIKE'),
      find.byType(ListView),
      const Offset(-200, 0),
    );
    await tester.tap(find.text('ADD BIKE'));
    expect(added, isTrue);
  });
}
