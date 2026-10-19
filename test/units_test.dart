import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:throttle/models/models.dart';
import 'package:throttle/providers/core.dart';
import 'package:throttle/providers/settings.dart';
import 'package:throttle/screens/profile_screen.dart';
import 'package:throttle/screens/ride_detail_screen.dart';
import 'package:throttle/services/local_ride_store.dart';
import 'package:throttle/units.dart';
import 'package:throttle/widgets/map_tiles.dart';

import 'support/fake_gps.dart';
import 'support/fake_supabase.dart';
import 'support/providers.dart';

late FakeSupabase backend;

Future<void> _arrive(WidgetTester tester) async {
  backend.release();
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  test('speeds and distances, in km or miles', () {
    expect(Units.metric.speedText(64.4), '64 km/h');
    expect(Units.imperial.speedText(64.4), '40 mph');
    expect(Units.metric.shortText(22.4), '22.4 km');
    expect(Units.imperial.shortText(22.4), '13.9 mi');
    expect(Units.imperial.totalText(1609.344), '1,000.0 mi');
    expect(Units.imperial.fixed(1.609344, 2), '1.00');
  });

  group('screens', () {
    setUpAll(() async {
      backend = await FakeSupabase.start(userId: 'me');
      MapTiles.debugProvider = BlankTiles();
    });

    setUp(() {
      LocalRideStore.debugReset();
      SharedPreferences.setMockInitialValues({});
      backend.reset();
      backend.tables
        ..['profiles'] = [Fixtures.profile()]
        ..['bikes'] = [Fixtures.bike()]
        ..['rides'] = [Fixtures.ride()]
        ..['ride_media'] = []
        ..['kudos'] = []
        ..['follows'] = [];
    });

    testWidgets('a ride reads "64 km/h" over "top speed", or in miles',
        (tester) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final item = FeedItem.fromJson(Fixtures.ride());
      Widget page(Units units) => withProviders(MaterialApp(
            builder: (_, child) => UnitsScope(units: units, child: child!),
            home: RideDetailScreen(item: item),
          ));

      await tester.pumpWidget(page(Units.metric));
      await _arrive(tester);
      expect(find.text('64 km/h'), findsOneWidget);
      expect(find.text('TOP SPEED'), findsOneWidget);
      expect(find.text('26 km/h'), findsOneWidget);
      expect(find.text('AVG SPEED'), findsOneWidget);
      expect(find.text('22.40'), findsOneWidget);
      expect(find.text('KM'), findsOneWidget);
      expect(find.textContaining('KM/H'), findsNothing);

      await tester.pumpWidget(page(Units.imperial));
      await _arrive(tester);
      expect(find.text('40 mph'), findsOneWidget);
      expect(find.text('16 mph'), findsOneWidget);
      expect(find.text('13.92'), findsOneWidget);
      expect(find.text('MI'), findsOneWidget);
    });

    testWidgets('the units are picked in Profile, and kept', (tester) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(withProviders(
          const MaterialApp(home: Scaffold(body: ProfileScreen()))));
      await _arrive(tester);
      final container =
          ProviderScope.containerOf(tester.element(find.byType(ProfileScreen)));
      expect(container.read(unitsProvider), Units.metric);

      await tester.ensureVisible(find.text('Miles · mph'));
      await tester.tap(find.text('Miles · mph'));
      await _arrive(tester);
      expect(container.read(unitsProvider), Units.imperial);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('units'), 'imperial');

      // Read back next time.
      final next = ProviderContainer.test(retry: noRetry);
      next.read(unitsProvider);
      await tester.pump();
      expect(next.read(unitsProvider), Units.imperial);
    });
  });
}
