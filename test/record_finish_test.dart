import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:throttle/providers/navigation.dart';
import 'package:throttle/screens/record_screen.dart';
import 'package:throttle/screens/share_ride_screen.dart';
import 'package:throttle/services/local_ride_store.dart';
import 'package:throttle/widgets/map_tiles.dart';
import 'package:throttle/widgets/bike_chooser.dart';
import 'package:throttle/widgets/live_ride_map.dart';
import 'package:throttle/widgets/ride_celebration.dart';

import 'support/fake_gps.dart';
import 'support/providers.dart';

void main() {
  testWidgets('after FINISH: the flag goes in while it saves, then the ride',
      (tester) async {
    final geo = FakeGeolocator();
    GeolocatorPlatform.instance = geo;
    MapTiles.debugProvider = BlankTiles();
    LocalRideStore.debugReset();
    addTearDown(() => MapTiles.debugProvider = null);
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(withProviders(
      const MaterialApp(home: Scaffold(body: RecordScreen())),
      tab: AppTab.record,
    ));
    await tester.pump();

    // Before the ride: the motorcycle chooser. Who can see the ride is
    // decided after it.
    expect(find.text('Choose your ride'), findsOneWidget);
    expect(find.byType(BikeChooser), findsOneWidget);
    expect(find.byType(LiveRideMap), findsNothing);
    expect(find.text('WHO CAN SEE THIS RIDE'), findsNothing);

    await tester.tap(find.text('START'));
    await tester.pump();

    // Ride ~150 m north at 18 km/h.
    final t0 = DateTime.now();
    for (var i = 0; i <= 30; i++) {
      geo.fixes.add(fixAt(t0.add(Duration(seconds: i)), i * 5.0));
      await tester.pump();
    }

    // During the ride: live map with the stats overlaid.
    expect(find.byType(LiveRideMap), findsOneWidget);
    expect(find.text('RECORDING'), findsOneWidget);
    // Speed and average are both 18 km/h at a steady 5 m/s.
    expect(find.text('18 km/h', findRichText: true), findsNWidgets(2));
    expect(find.text('0.15 km', findRichText: true), findsOneWidget);
    final map = tester.widget<LiveRideMap>(find.byType(LiveRideMap));
    expect(map.trail.length, greaterThan(10)); // a point every ~10 m here
    expect(map.here!.latitude, closeTo(27.7 + 150 / 111320, 1e-9));

    await tester.tap(find.text('PAUSE'));
    await tester.pump();
    expect(find.text('PAUSED'), findsOneWidget);
    expect(find.text('RESUME'), findsOneWidget);

    await tester.tap(find.text('FINISH'));
    await tester.pump(); // one frame: nothing waits on the network
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // The flag goes in straight away, while the ride saves; NEXT is all
    // there is to do.
    final celebration = find.byType(RideCelebration);
    expect(celebration, findsOneWidget);
    Finder inCelebration(Finder f) =>
        find.descendant(of: celebration, matching: f);
    expect(inCelebration(find.text('Ride complete.')), findsOneWidget);
    expect(inCelebration(find.text('NEXT')), findsOneWidget);
    for (final gone in ['Share', 'DISCARD', 'DONE', 'VIEW RIDE', 'RESUME']) {
      expect(inCelebration(find.text(gone)), findsNothing, reason: gone);
    }
    expect(tester.getRect(inCelebration(find.text('NEXT'))).bottom,
        lessThan(844)); // on screen without scrolling (390×844 phone)
    // Nothing is lost if the app closes now: the ride waits on the phone.
    expect(LocalRideStore.debugDraft, isNotNull);

    // The ride: it says how saving went, with Share, DISCARD and DONE.
    await tester.tap(inCelebration(find.text('NEXT')));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(RideCelebration), findsNothing);
    // Supabase isn't initialised in tests, so saving fails, visibly.
    expect(find.textContaining('Couldn\'t save this ride'), findsOneWidget);
    expect(find.text('TRY AGAIN'), findsOneWidget); // can try again
    expect(find.text('DISCARD'), findsOneWidget);
    expect(find.bySemanticsLabel('Share'), findsOneWidget);
    expect(find.textContaining('0.15'), findsWidgets);
    await tester.scrollUntilVisible(find.text('WHO CAN SEE THIS RIDE'), 300,
        scrollable: find.byType(Scrollable).first);
    for (final option in ['Public', 'Followers', 'Private']) {
      expect(find.text(option), findsOneWidget);
    }
    expect(find.text('Ride card'), findsOneWidget);

    // Sharing doesn't depend on saving.
    await tester.tap(find.bySemanticsLabel('Share'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(ShareRideScreen), findsOneWidget);
    expect(find.text('Share ride'), findsOneWidget); // share screen app bar
    expect(
        find.textContaining('0.15'), findsWidgets); // same distance on the card

    await geo.fixes.close();
  });
}
