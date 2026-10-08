import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:throttle/models/models.dart';
import 'package:throttle/screens/share_ride_screen.dart';

FeedItem _ride({String? bikePhotoUrl, bool track = true}) => FeedItem(
      ride: RideRecord(
        id: 'r1',
        userId: 'u1',
        title: 'Nagarkot sunrise run',
        visibility: RideVisibility.public,
        distanceKm: 42.384,
        movingTimeSecs: 5400,
        avgSpeedKmh: 28.3,
        maxSpeedKmh: 71.6,
        elevationM: 820,
        startedAt: DateTime(2026, 10, 9, 6),
      ),
      rider: const Profile(id: 'u1'),
      bikeName: 'Yamaha MT-15',
      bikePhotoUrl: bikePhotoUrl,
      points: track
          ? const [
              TrackPoint(lat: 27.67, lng: 85.42),
              TrackPoint(lat: 27.69, lng: 85.45),
              TrackPoint(lat: 27.71, lng: 85.52),
            ]
          : const [],
    );

Future<void> _pump(WidgetTester tester, FeedItem item) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: ShareRideScreen(item: item)));
  await tester.pump();
}

void main() {
  testWidgets('card shows ride stats and background options', (tester) async {
    await _pump(tester, _ride(track: false));
    expect(find.text('THROTTLE'), findsOneWidget);
    expect(find.text('9 Oct 2026'), findsOneWidget);
    expect(find.textContaining('42.38'), findsOneWidget);
    expect(find.text('1h 30m'), findsOneWidget);
    expect(find.text('Yamaha MT-15'), findsOneWidget);
    // No bike photo and no track: only "your photo" and "plain".
    expect(find.text('Bike photo'), findsNothing);
    expect(find.text('Route map'), findsNothing);
    expect(find.text('Your photo…'), findsOneWidget);
    expect(find.text('Plain'), findsOneWidget);
  });

  testWidgets('bike photo is the default background when the bike has one',
      (tester) async {
    await _pump(tester, _ride(bikePhotoUrl: 'https://example.com/bike.jpg'));
    final chip = tester.widget<ChoiceChip>(
      find.ancestor(
          of: find.text('Bike photo'), matching: find.byType(ChoiceChip)),
    );
    expect(chip.selected, isTrue);
    expect(find.text('Route map'), findsOneWidget);
  });

  testWidgets('captures a 1080×1350 image', (tester) async {
    await _pump(tester, _ride(track: false));
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find
          .ancestor(
              of: find.text('THROTTLE'), matching: find.byType(RepaintBoundary))
          .first,
    );
    final image = await tester.runAsync(() => boundary.toImage(pixelRatio: 3));
    expect(image!.width, 1080);
    expect(image.height, 1350);
    image.dispose();
  });
}
