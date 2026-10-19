import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:throttle/models/models.dart';
import 'package:throttle/repositories/ride_repository.dart';
import 'package:throttle/screens/ride_detail_screen.dart';
import 'package:throttle/screens/ride_journal_screen.dart';
import 'package:throttle/services/local_ride_store.dart';
import 'package:throttle/widgets/map_tiles.dart';
import 'package:throttle/widgets/tracked_route_map.dart';

import 'support/fake_gps.dart';
import 'support/fake_supabase.dart';
import 'support/providers.dart';

late FakeSupabase backend;

/// A ride north from Bhaktapur, a point every ~100 m.
final _track = [
  for (var i = 0; i <= 120; i++)
    TrackPoint(
      lat: 27.67 + i * 100 / 111320,
      lng: 85.42,
      t: DateTime.utc(2026, 10, 9, 1).add(Duration(seconds: i * 10)),
    ),
];

/// What the lists ask for, per request.
Iterable<String?> get _selects => backend.requests
    .where((r) => r.url.pathSegments.last == 'rides')
    .map((r) => r.url.queryParameters['select']);

Future<void> _arrive(WidgetTester tester) async {
  backend.release();
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  setUpAll(() async {
    backend = await FakeSupabase.start(userId: 'me');
    MapTiles.debugProvider = BlankTiles();
  });

  setUp(() {
    LocalRideStore.debugReset();
    RideRepository.debugReset();
    backend.reset();
    backend.tables
      ..['rides'] = [
        Fixtures.ride()
          ..['track'] = {
            'points': encodeTrack(_track),
            'preview': {
              'v': 2,
              'p': [
                for (final p in [_track.first, _track[60], _track.last])
                  [p.lat, p.lng],
              ],
            },
          },
      ]
      ..['ride_tracks'] = [
        {'ride_id': 'r1', 'points': encodeTrack(_track)},
      ]
      ..['ride_media'] = []
      ..['kudos'] = [];
  });

  testWidgets('lists load a preview of each track, not the whole of it',
      (tester) async {
    final items = await RideRepository().feed();
    expect(items.single.previewTrack, isTrue);
    expect(items.single.points, hasLength(3));
    expect(_selects.single, contains('track:ride_tracks(preview)'));
    expect(_selects.single, isNot(contains('points')));
  });

  testWidgets('until the server has previews: whole tracks, asked once',
      (tester) async {
    backend.missingColumns.add('preview');
    final first = await RideRepository().ridesForUser('me');
    expect(first.single.previewTrack, isFalse);
    expect(first.single.points, hasLength(_track.length));
    expect(_selects.last, contains('track:ride_tracks(points)'));

    // Later lists go straight to whole tracks.
    backend.requests.clear();
    await RideRepository().feed();
    expect(_selects, hasLength(1));
  });

  testWidgets('the ride\'s page loads the whole track, and its journal has it',
      (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final item = (await RideRepository().feedItem('r1'))!;
    expect(item.points, hasLength(3));

    await tester.pumpWidget(
        withProviders(MaterialApp(home: RideDetailScreen(item: item))));
    final map = find.byType(TrackedRouteMap).first;
    expect(tester.widget<TrackedRouteMap>(map).points, hasLength(3));
    await _arrive(tester);
    expect(
        tester.widget<TrackedRouteMap>(map).points, hasLength(_track.length));

    await tester.scrollUntilVisible(find.text('Start a Ride Journal'), 300,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Start a Ride Journal'));
    await _arrive(tester);
    final journal =
        tester.widget<RideJournalScreen>(find.byType(RideJournalScreen));
    expect(journal.item.points, hasLength(_track.length));
    expect(journal.item.previewTrack, isFalse);
  });
}
