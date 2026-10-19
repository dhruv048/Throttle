import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:throttle/models/models.dart';
import 'package:image/image.dart' as img;
import 'package:throttle/screens/share_ride_screen.dart';
import 'package:throttle/widgets/share_card.dart';
import 'package:throttle/widgets/track_shape.dart';
import 'package:throttle/widgets/map_tiles.dart';

import 'support/fake_gps.dart';

FeedItem _ride(
        {String? bikePhotoUrl,
        bool track = true,
        String title = 'Nagarkot sunrise run'}) =>
    FeedItem(
      ride: RideRecord(
        id: 'r1',
        userId: 'u1',
        title: title,
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

Future<void> _pump(WidgetTester tester, FeedItem item,
    {ValueNotifier<ShareCardDesign>? design}) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
      MaterialApp(home: ShareRideScreen(item: item, design: design)));
  await tester.pump();
}

/// One card on its own, at its full size.
Future<void> _pumpCard(
    WidgetTester tester, FeedItem item, ShareCardDesign design) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Center(
      child: SizedBox.fromSize(
        size: ShareCard.size,
        child: ShareCard(item: item, design: design),
      ),
    ),
  ));
  await tester.pump();
}

RenderRepaintBoundary _card(WidgetTester tester) =>
    tester.renderObject<RenderRepaintBoundary>(
      find
          .ancestor(
              of: find.text('THROTTLE'), matching: find.byType(RepaintBoundary))
          .first,
    );

void main() {
  testWidgets('a card shows the ride\'s stats', (tester) async {
    await _pumpCard(tester, _ride(track: false),
        const ShareCardDesign(ShareBackground.plain));
    expect(find.text('THROTTLE'), findsOneWidget);
    expect(find.text('NAGARKOT SUNRISE RUN'), findsOneWidget);
    expect(find.text('9 OCT 2026'), findsOneWidget);
    expect(find.text('42.4'), findsOneWidget);
    expect(find.text('1h 30m'), findsOneWidget);
    expect(find.text('Yamaha MT-15'), findsOneWidget);
  });

  testWidgets('every card, two to a row, and the background options',
      (tester) async {
    await _pump(tester, _ride(track: false));
    expect(find.text('Tap a card to share it.'), findsOneWidget);
    for (final style in ShareCardStyle.values) {
      await tester.scrollUntilVisible(find.text(style.label), 200,
          scrollable: find.byType(Scrollable).last);
      expect(find.text(style.label), findsOneWidget);
    }
    // Two to a row.
    final poster = tester.getTopLeft(find.text(ShareCardStyle.poster.label));
    final cockpit = tester.getTopLeft(find.text(ShareCardStyle.cockpit.label));
    expect(cockpit.dy, closeTo(poster.dy, 1));
    expect(cockpit.dx, greaterThan(poster.dx));
    // No bike photo and no track: only "your photo" and "plain".
    expect(find.text('Bike photo'), findsNothing);
    expect(find.text('Route map'), findsNothing);
    expect(find.text('Your photo…'), findsOneWidget);
    expect(find.text('Plain'), findsOneWidget);
  });

  testWidgets('original: the speeds are the headline, the route beside them',
      (tester) async {
    await _pumpCard(
        tester,
        _ride(),
        const ShareCardDesign(ShareBackground.plain,
            style: ShareCardStyle.classic));
    final top = tester.getRect(find.text('72 km/h'));
    final avg = tester.getRect(find.text('28 km/h'));
    final distance = tester.getRect(find.text('42.38 km'));
    expect(find.text('TOP SPEED'), findsOneWidget);
    expect(find.text('AVG SPEED'), findsOneWidget);
    // Bigger than the other stats, which sit below them.
    expect(top.height, greaterThan(distance.height * 1.5));
    expect(avg.height, greaterThan(distance.height * 1.5));
    expect(distance.top, greaterThan(avg.bottom));

    final route = tester.getRect(find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is TrackShapePainter));
    expect(route.left, greaterThan(top.right));
    expect(route.top, lessThan(avg.bottom));
    expect(route.bottom, greaterThan(top.top));
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
    final image =
        await tester.runAsync(() => _card(tester).toImage(pixelRatio: 3));
    expect(image!.width, 1080);
    expect(image.height, 1350);
    image.dispose();
  });

  testWidgets('the card posted with a ride is a 1080×1350 JPEG',
      (tester) async {
    await _pump(tester, _ride(track: false));
    final jpeg = await tester.runAsync(() async {
      final image = await _card(tester).toImage(pixelRatio: 3);
      try {
        return await encodeJpeg(image);
      } finally {
        image.dispose();
      }
    });
    final decoded = img.decodeJpg(jpeg!)!;
    expect(decoded.width, 1080);
    expect(decoded.height, 1350);
    expect(jpeg.length, lessThan(1024 * 1024));
  });

  testWidgets('background picked here carries over to the posted card',
      (tester) async {
    MapTiles.debugProvider = BlankTiles();
    addTearDown(() => MapTiles.debugProvider = null);
    final design = ValueNotifier(const ShareCardDesign(ShareBackground.map));
    addTearDown(design.dispose);
    await _pump(tester, _ride(), design: design);
    expect(
        tester
            .widget<ChoiceChip>(find.ancestor(
                of: find.text('Route map'), matching: find.byType(ChoiceChip)))
            .selected,
        isTrue);

    await tester.ensureVisible(find.text('Plain')); // the chips scroll
    await tester.tap(find.text('Plain'));
    await tester.pump();
    expect(design.value.background, ShareBackground.plain);
  });

  testWidgets(
      'every style lays out on every background, with or without a '
      'track', (tester) async {
    MapTiles.debugProvider = BlankTiles();
    addTearDown(() => MapTiles.debugProvider = null);
    final design = ValueNotifier(const ShareCardDesign(ShareBackground.plain));
    addTearDown(design.dispose);
    for (final track in [true, false]) {
      // Every style is on screen at once.
      await _pump(tester, _ride(track: track), design: design);
      for (final background in [
        ShareBackground.plain,
        ShareBackground.map,
        ShareBackground.photo,
      ]) {
        design.value = ShareCardDesign(background, photo: BlankTiles.png);
        await tester.pump();
        expect(tester.takeException(), isNull,
            reason: 'on $background, track: $track');
        expect(find.text('THROTTLE', skipOffstage: false),
            findsNWidgets(ShareCardStyle.values.length));
      }
    }
  });

  testWidgets(
      'tapping a card shares it, and makes it the one posted with the ride',
      (tester) async {
    final design = ValueNotifier(
        ShareCardDesign(ShareBackground.photo, photo: BlankTiles.png));
    addTearDown(design.dispose);
    await _pump(tester, _ride(), design: design);
    expect(find.text('DEPART', skipOffstage: false), findsOneWidget);
    expect(find.text('06:00', skipOffstage: false), findsOneWidget);
    expect(find.text('07:30', skipOffstage: false),
        findsOneWidget); // start + moving time

    await tester.ensureVisible(find.text('Ride pass'));
    await tester.pump();
    await tester.tap(find.text('Ride pass'));
    await tester.pump();
    expect(design.value.style, ShareCardStyle.pass);
    // Same background and photo.
    expect(design.value.background, ShareBackground.photo);
    expect(design.value.photo, BlankTiles.png);
    expect(find.byType(CircularProgressIndicator), findsOneWidget); // sharing
    // Waits for the card's photo and fonts at most 10 s.
    await tester.pump(const Duration(seconds: 11));
    await tester.pump(const Duration(seconds: 5));
  });

  test('the app\'s default title gives way to when the ride was', () {
    expect(_ride(title: 'Ride · 42.4 km').headline, 'Friday morning ride');
    expect(
        _ride(title: 'Nagarkot sunrise run').headline, 'Nagarkot sunrise run');
  });
}
