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

    await tester.tap(find.text('ADD BIKE'));
    expect(added, isTrue);
  });

  testWidgets('two bikes to a row, the add cell after them', (tester) async {
    const bikes = [
      BikeRecord(id: 'a', userId: 'u', name: 'Yamaha MT-15'),
      BikeRecord(id: 'b', userId: 'u', name: 'Royal Enfield Himalayan'),
      BikeRecord(id: 'c', userId: 'u', name: 'KTM 390 Duke'),
    ];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: BikeChooser(
            bikes: bikes,
            selectedId: 'a',
            onSelect: (_) {},
            onAdd: () {},
          ),
        ),
      ),
    ));

    Offset at(String text) => tester.getTopLeft(find.text(text));
    // Side by side (the picked one's thicker outline nudges it a little)…
    expect(at('Royal Enfield Himalayan').dy, closeTo(at('Yamaha MT-15').dy, 2));
    expect(
        at('Royal Enfield Himalayan').dx, greaterThan(at('Yamaha MT-15').dx));
    // …then the next row.
    expect(at('KTM 390 Duke').dy, greaterThan(at('Yamaha MT-15').dy));
    expect(at('KTM 390 Duke').dx, closeTo(at('Yamaha MT-15').dx, 2));
    expect(tester.getCenter(find.text('ADD BIKE')).dy,
        greaterThan(at('Yamaha MT-15').dy));
  });
}
