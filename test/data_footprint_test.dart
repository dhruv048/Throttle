import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:throttle/models/models.dart';
import 'package:throttle/providers/rider.dart';
import 'package:throttle/services/local_ride_store.dart';
import 'package:throttle/services/place_names.dart';

/// An hour's ride: a point every ~10 m, every 2 s, climbing.
final _track = [
  for (var i = 0; i < 1800; i++)
    TrackPoint(
      lat: 27.6712345 + i * 0.0000937,
      lng: 85.4209876 + i * 0.0000411,
      t: DateTime.utc(2026, 10, 9, 1).add(Duration(seconds: i * 2)),
      elev: 1320.5 + i * 0.13,
      accuracy: 4.8,
    ),
];

PendingRide _ride({String id = 'r1', bool synced = false, String? bikeId}) =>
    PendingRide(
      localId: id,
      userId: 'me',
      title: 'Ride',
      visibility: RideVisibility.public,
      distanceKm: 12.5,
      movingTimeSecs: 3600,
      avgSpeedKmh: 12.5,
      maxSpeedKmh: 60,
      bikeName: 'KTM 390 Duke',
      bikeId: bikeId,
      points: _track,
      createdAt: DateTime.now(),
      synced: synced,
      remoteId: synced ? 'remote-$id' : null,
    );

void main() {
  group('tracks are stored compactly', () {
    test('a third of the size, and read back to 0.1 s and 0.1 m', () {
      final compact = jsonEncode(encodeTrack(_track));
      final old = jsonEncode([for (final p in _track) p.toJson()]);
      expect(compact.length, lessThan(old.length * 0.45));

      final back = decodeTrack(jsonDecode(compact));
      expect(back, hasLength(_track.length));
      for (final i in [0, 1, 900, 1799]) {
        expect(back[i].lat, closeTo(_track[i].lat, 1e-6));
        expect(back[i].lng, closeTo(_track[i].lng, 1e-6));
        expect(back[i].t!.difference(_track[i].t!).inMilliseconds.abs(),
            lessThanOrEqualTo(50));
        expect(back[i].elev, closeTo(_track[i].elev!, 0.05));
      }
    });

    test('older tracks still read, and points without a time or height', () {
      final old = [for (final p in _track.take(3)) p.toJson()];
      expect(decodeTrack(jsonDecode(jsonEncode(old))).length, 3);

      const bare = [TrackPoint(lat: 27.7, lng: 85.3)];
      final encoded = encodeTrack(bare);
      expect(encoded['p'], [
        [27.7, 85.3]
      ]);
      expect(decodeTrack(encoded).single.t, isNull);
      expect(decodeTrack(null), isEmpty);
    });
  });

  group('the phone\'s upload queue stays small', () {
    setUp(LocalRideStore.debugReset);

    test('an uploaded ride is kept without its track', () async {
      final store = LocalRideStore();
      await store.enqueue(_ride());
      expect((await store.loadAll()).single.points, hasLength(1800));

      await store.markSynced('r1', 'remote-r1');
      final kept = (await store.loadAll()).single;
      expect(kept.synced, isTrue);
      expect(kept.remoteId, 'remote-r1');
      expect(kept.points, isEmpty);
      expect(LocalRideStore.debugMemory!.length, lessThan(1000));
    });

    test('until its photos are up, then a couple of weeks', () async {
      final store = LocalRideStore();
      final old = PendingRide.fromJson({
        ..._ride(id: 'old', synced: true).toJson(),
        'createdAt':
            DateTime.now().subtract(const Duration(days: 30)).toIso8601String(),
      });
      final withPhoto = PendingRide.fromJson({
        ...old.toJson(),
        'localId': 'photo',
        'media': [
          const PendingMedia(id: 'p1', extension: 'jpg').toJson(),
        ],
      });
      await store.saveAll([old, withPhoto, _ride(id: 'new')]);
      final kept = await store.loadAll();
      expect(kept.map((r) => r.localId), ['photo', 'new']);
      expect(await store.withUploadsLeft(), hasLength(1));
    });
  });

  test('rides still on the phone count toward their bike straight away', () {
    const bikes = [
      BikeRecord(id: 'b1', userId: 'me', name: 'KTM 390 Duke', riddenKm: 100),
      BikeRecord(id: 'b2', userId: 'me', name: 'Himalayan 450', riddenKm: 5),
    ];
    final shown = withRidesOnPhone(bikes, [
      _ride(id: 'a', bikeId: 'b2'),
      _ride(id: 'b'), // no bike picked: the primary (first) one
    ]);
    expect(shown.map((b) => b.riddenKm), [112.5, 17.5]);
    expect(withRidesOnPhone(bikes, const []), same(bikes));
  });

  group('place names', () {
    test('the settlement first, then wider areas', () {
      expect(
          PlaceNames.nameFrom({
            'name': 'Some Road',
            'address': {
              'road': 'Some Road',
              'town': 'Nagarkot',
              'county': 'Bhaktapur',
              'country': 'Nepal',
            },
          }),
          'Nagarkot');
      expect(
          PlaceNames.nameFrom({
            'address': {'county': 'Kaski', 'state': 'Gandaki'},
          }),
          'Kaski');
      expect(PlaceNames.nameFrom({'error': 'Unable to geocode'}), isNull);
    });

    test('where a ride went, as far as it\'s known', () {
      expect(placesLine('Bhaktapur', 'Nagarkot'), 'Bhaktapur → Nagarkot');
      expect(placesLine('Pokhara', 'Pokhara'), 'Around Pokhara');
      expect(placesLine(null, 'Nagarkot'), 'To Nagarkot');
      expect(placesLine('Bhaktapur', null), 'From Bhaktapur');
      expect(placesLine(null, null), isNull);
    });
  });
}
