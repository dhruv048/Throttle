import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart' show XFile;
import 'package:throttle/models/models.dart';
import 'package:throttle/providers/journal.dart';
import 'package:throttle/providers/navigation.dart';
import 'package:throttle/repositories/ride_repository.dart';
import 'package:throttle/screens/record_screen.dart';
import 'package:throttle/screens/ride_detail_screen.dart';
import 'package:throttle/services/local_ride_store.dart';
import 'package:throttle/services/ride_sync_service.dart';
import 'package:throttle/widgets/map_tiles.dart';
import 'package:throttle/widgets/ride_celebration.dart';
import 'package:throttle/widgets/skeleton.dart';

import 'support/fake_gps.dart';
import 'support/fake_places.dart';
import 'support/fake_supabase.dart';
import 'support/providers.dart';

late FakeSupabase backend;

/// Lets requests through and settles the UI.
Future<void> _arrive(WidgetTester tester) async {
  backend.release();
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Lets a page, sheet or dialog animate in or out.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Where the test ride sets off from and reaches.
final _places = FakePlaceNames(names: {
  '27.700,85.300': 'Bhaktapur',
  '27.701,85.300': 'Nagarkot',
});

Future<FakeGeolocator> _pumpRecord(WidgetTester tester,
    {bool active = true, List<XFile> picked = const []}) async {
  final geo = FakeGeolocator();
  GeolocatorPlatform.instance = geo;
  addTearDown(geo.fixes.close);
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(withProviders(
    const MaterialApp(home: Scaffold(body: RecordScreen())),
    tab: active ? AppTab.record : AppTab.home,
    places: _places,
    overrides: [pickJournalMediaProvider.overrideWithValue(() async => picked)],
  ));
  await _arrive(tester);
  return geo;
}

final _t0 = DateTime.now();

/// [metres] north at 18 km/h from [fromM], a fix a second from [at] seconds.
Future<void> _rideNorth(WidgetTester tester, FakeGeolocator geo,
    {double fromM = 0, double metres = 150, int at = 0}) async {
  for (var i = 0; i <= metres / 5; i++) {
    geo.fixes.add(fixAt(_t0.add(Duration(seconds: at + i)), fromM + i * 5.0));
    await tester.pump();
  }
}

/// START, ~150 m north at 18 km/h, FINISH.
Future<void> _ride(WidgetTester tester, FakeGeolocator geo) async {
  await tester.tap(find.text('START'));
  await tester.pump();
  await _rideNorth(tester, geo);
  await tester.tap(find.text('FINISH'));
  await _settle(tester);
}

/// The celebration after FINISH.
final _celebration = find.byType(RideCelebration);
Finder _celebrating(Finder f) => find.descendant(of: _celebration, matching: f);

/// Lets the save go through.
Future<void> _saved(WidgetTester tester) async {
  await _arrive(tester);
  await _settle(tester);
}

/// NEXT: from the celebration to the ride's page underneath.
Future<void> _viewRide(WidgetTester tester) async {
  await tester.tap(_celebrating(find.text('NEXT')));
  await _settle(tester);
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
}

/// The post-ride form's title and "about the ride" fields.
Finder get _titleField => find.byType(TextField).at(0);
Finder get _storyField => find.byType(TextField).at(1);

/// A small JPEG that says where it was taken, as phone cameras do.
Uint8List _jpegAt(double lat, double lng) {
  final image = img.Image(width: 8, height: 8);
  img.IfdValueRational dms(double v) {
    final d = v.abs().floor();
    final m = ((v.abs() - d) * 60).floor();
    final s = ((v.abs() - d - m / 60) * 3600 * 1000).round();
    return img.IfdValueRational(d, 1)
      ..value.add(img.IfdValueRational(m, 1).value.single)
      ..value.add(img.IfdValueRational(s, 1000).value.single);
  }

  image.exif.gpsIfd.data[0x0001] = img.IfdValueAscii('N');
  image.exif.gpsIfd.data[0x0002] = dms(lat);
  image.exif.gpsIfd.data[0x0003] = img.IfdValueAscii('E');
  image.exif.gpsIfd.data[0x0004] = dms(lng);
  return img.encodeJpg(image);
}

PendingRide _finished({String localId = 'ride-1', double km = 12.3}) =>
    PendingRide(
      localId: localId,
      userId: 'me',
      title: 'Ride · $km km',
      visibility: RideVisibility.private,
      distanceKm: km,
      movingTimeSecs: 1800,
      avgSpeedKmh: 24.6,
      maxSpeedKmh: 61,
      elevationM: 120,
      bikeName: 'KTM 390 Duke',
      bikeId: 'b1',
      points: const [
        TrackPoint(lat: 27.67, lng: 85.42),
        TrackPoint(lat: 27.71, lng: 85.52),
      ],
      createdAt: DateTime(2026, 10, 10, 9),
      startedAt: DateTime(2026, 10, 10, 8, 30),
      endedAt: DateTime(2026, 10, 10, 9),
    );

void main() {
  setUpAll(() async {
    backend = await FakeSupabase.start(userId: 'me');
    MapTiles.debugProvider = BlankTiles();
  });

  setUp(() {
    LocalRideStore.debugReset();
    backend.reset();
    backend.tables
      ..['profiles'] = [Fixtures.profile()]
      ..['bikes'] = [Fixtures.bike()]
      ..['rides'] = []
      ..['ride_tracks'] = [];
  });

  group('after the ride', () {
    testWidgets(
        'FINISH saves it and plants its flag; changes go to the saved ride',
        (tester) async {
      backend.tables['bikes']!.add(Fixtures.bike(
          id: 'b2', name: 'Himalayan 450', primary: false, riddenKm: 80));
      final geo = await _pumpRecord(tester);
      backend.hold = true; // to see it saving
      await _ride(tester, geo);

      // The flag goes in at once, while it saves; NEXT is all there is.
      expect(_celebration, findsOneWidget);
      expect(_celebrating(find.text('NEXT')), findsOneWidget);
      expect(_celebrating(find.text('DONE')), findsNothing);
      await _arrive(tester);
      expect(_celebrating(find.text('FLAG #1 PLANTED')), findsOneWidget);
      expect(_celebrating(find.text('Ride complete.')), findsOneWidget);
      expect(_celebrating(find.text('First flag')), findsOneWidget);
      expect(_celebrating(find.text('BADGE EARNED')), findsOneWidget);
      expect(_celebrating(find.textContaining('You reached Nagarkot')),
          findsOneWidget);

      // Named after where it went.
      final row = backend.tables['rides']!.single;
      expect(row['title'], 'Ride to Nagarkot');
      expect(row['visibility'], 'public');
      expect(row['bike_id'], 'b1');
      expect(row['start_place'], 'Bhaktapur');
      expect(row['end_place'], 'Nagarkot');
      expect(backend.tables['ride_tracks'], hasLength(1));
      expect(LocalRideStore.debugDraft, isNull);

      // The ride: saved by itself; what it's called, what happened, the
      // bike, who sees it.
      await _viewRide(tester);
      expect(_celebration, findsNothing);
      expect(find.textContaining('Saved to your profile'), findsOneWidget);
      expect(find.text('DISCARD'), findsOneWidget);
      expect(find.text('RESUME'), findsOneWidget);
      expect(tester.widget<TextField>(_titleField).decoration!.hintText,
          'Ride to Nagarkot');
      expect(find.text('Bhaktapur → Nagarkot'), findsWidgets);
      await tester.enterText(_titleField, 'sunrise loop');
      await tester.enterText(_storyField, 'Fog lifting off the hills.');
      await _tapVisible(tester, find.byType(DropdownButtonFormField<String>));
      await _settle(tester);
      await tester.tap(find.text('Himalayan 450').last);
      await _settle(tester);
      await _tapVisible(tester, find.text('Followers'));
      await tester.pump(const Duration(seconds: 1)); // typing pauses
      await _arrive(tester);

      expect(row['title'], 'Sunrise loop');
      expect(row['journal'], 'Fog lifting off the hills.');
      expect(row['visibility'], 'followers');
      expect(row['bike_id'], 'b2');
      expect(backend.tables['rides'], hasLength(1));

      await _tapVisible(tester, find.text('DONE'));
      await _settle(tester);
      expect(find.text('Choose your ride'), findsOneWidget);
    });

    testWidgets('RESUME carries on the same ride, with what was added',
        (tester) async {
      final geo = await _pumpRecord(tester);
      await _ride(tester, geo);
      await _saved(tester);
      await _viewRide(tester);
      expect(find.text('0.15'), findsOneWidget);
      await tester.enterText(_titleField, 'Sunrise loop');

      await _tapVisible(tester, find.text('RESUME'));
      await _settle(tester);
      expect(find.text('RECORDING'), findsOneWidget);
      expect(find.text('0.15 km', findRichText: true), findsOneWidget);
      expect(LocalRideStore.debugLive, isNotNull); // a ride in progress again

      await _rideNorth(tester, geo, fromM: 150, metres: 100, at: 60);
      await tester.tap(find.text('FINISH'));
      await _settle(tester);
      await _saved(tester);

      // Still one ride, now longer, with its title.
      final row = backend.tables['rides']!.single;
      expect(row['distance_km'], closeTo(0.25, 0.01));
      expect(row['title'], 'Sunrise loop');
      expect(backend.tables['ride_tracks'], hasLength(1));
      expect(
          decodeTrack(backend.tables['ride_tracks']!.single['points']).length,
          greaterThan(20));
      await _viewRide(tester);
      expect(find.text('0.25'), findsOneWidget);
      expect(find.text('Sunrise loop'), findsOneWidget);
    });

    testWidgets('photos added to the ride go up into its journal',
        (tester) async {
      final geo = await _pumpRecord(tester, picked: [
        // Taken 100 m into the ride.
        XFile.fromData(_jpegAt(27.7 + 100 / 111320, 85.3),
            path: '/picked/IMG_0001.jpg'),
        XFile.fromData(Uint8List.fromList([0, 0, 0, 1]),
            path: '/picked/clip.MOV'),
        XFile.fromData(Uint8List.fromList([1]), path: '/picked/notes.pdf'),
      ]);
      await _ride(tester, geo);
      await _saved(tester);
      await _viewRide(tester);
      // The ride card comes first.
      expect(find.text('Ride card'), findsOneWidget);
      await _tapVisible(
          tester, find.byIcon(Icons.add_photo_alternate_outlined));
      for (var i = 0; i < 3; i++) {
        await _arrive(tester);
      }
      expect(find.text('On the route'), findsOneWidget);
      expect(find.text('Video'), findsOneWidget);
      expect(find.textContaining('1 skipped'), findsOneWidget);

      final rideId = backend.tables['rides']!.single['id'];
      final media = backend.tables['ride_media']!;
      expect(media, hasLength(2));
      expect(media[0]['ride_id'], rideId);
      expect(media[0]['kind'], 'photo');
      expect(media[0]['lat'], closeTo(27.7 + 100 / 111320, 1e-6));
      expect(media[1]['kind'], 'video');
      expect(backend.storage.keys.map((k) => k.split('.').last).toList(),
          ['jpg', 'mov']);
      expect(
          backend.storage.keys
              .every((k) => k.startsWith('ride-media/me/$rideId/')),
          isTrue);
      expect(LocalRideStore.debugMedia, isEmpty); // uploaded

      // Taken off again: out of the journal too.
      await tester.tap(find.bySemanticsLabel('Remove').first);
      await _arrive(tester);
      expect(backend.tables['ride_media'], hasLength(1));
    });

    testWidgets('DISCARD deletes the saved ride', (tester) async {
      final geo = await _pumpRecord(tester);
      await _ride(tester, geo);
      await _saved(tester);
      expect(backend.tables['rides'], hasLength(1));

      await _viewRide(tester);
      await tester.tap(find.text('DISCARD'));
      await _settle(tester);
      expect(find.text('Discard this ride?'), findsOneWidget);
      await tester.tap(find.text('Discard'));
      await _arrive(tester);
      await _settle(tester);

      expect(find.text('Choose your ride'), findsOneWidget);
      expect(_celebration, findsNothing);
      expect(backend.tables['rides'], isEmpty);
      expect(await LocalRideStore().loadAll(), isEmpty);
    });

    testWidgets('a ride left unsaved comes back after the app restarts, saved',
        (tester) async {
      LocalRideStore.debugDraft = jsonEncode({
        ..._finished().copyWith(journal: 'Fog lifting.').toJson(),
        'resume': {'tracker': <String, dynamic>{}},
      });
      await _pumpRecord(tester, active: false);
      await _arrive(tester);

      expect(find.text('12.30'), findsOneWidget);
      // With the choices it was left with.
      expect(find.text('Only you can see it.'), findsOneWidget);
      expect(find.text('Fog lifting.'), findsOneWidget);
      final row = backend.tables['rides']!.single;
      expect(row['visibility'], 'private');
      expect(row['journal'], 'Fog lifting.');
      expect(find.text('RESUME'), findsOneWidget);
      // Not shown off over another tab.
      expect(_celebration, findsNothing);
    });

    testWidgets('an accidental START/FINISH isn\'t saved by itself',
        (tester) async {
      final geo = await _pumpRecord(tester);
      await tester.tap(find.text('START'));
      await tester.pump();
      await tester.tap(find.text('FINISH'));
      await _settle(tester);
      await _arrive(tester);
      expect(_celebration, findsNothing);
      expect(backend.tables['rides'], isEmpty);
      expect(find.text('SAVE RIDE'), findsOneWidget);
      expect(geo.fixes.hasListener, isFalse); // GPS off till the next ride
    });

    testWidgets('a ride the app was already saving isn\'t offered again',
        (tester) async {
      final ride = _finished();
      LocalRideStore.debugDraft = jsonEncode(ride.toJson());
      LocalRideStore.debugMemory = jsonEncode([ride.toJson()]);
      await _pumpRecord(tester, active: false);

      expect(find.text('Choose your ride'), findsOneWidget);
      expect(LocalRideStore.debugDraft, isNull);
    });
  });

  group('photos with a ride', () {
    testWidgets('offline, wait on the phone with it, then sync',
        (tester) async {
      final photo = Uint8List.fromList([0xFF, 0xD8, 9, 0xFF, 0xD9]);
      const media = PendingMedia(id: 'p1', extension: 'jpg');
      LocalRideStore.debugMedia['ride-1/p1.jpg'] = photo;
      backend.offline = true;
      final saving = RideRepository().saveRide(
          _finished().copyWith(journal: 'Fog lifting.', media: [media]));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(seconds: 1)); // request retries
      }
      expect((await saving).synced, isFalse);
      expect(LocalRideStore.debugMedia.keys, ['ride-1/p1.jpg']);

      backend.offline = false;
      final syncing = RideSyncService().syncPending();
      for (var i = 0; i < 3; i++) {
        await _arrive(tester);
      }
      expect(await syncing, 1);
      expect(backend.tables['rides']!.single['journal'], 'Fog lifting.');
      final row = backend.tables['ride_media']!.single;
      expect(row['storage_path'], 'me/rides-1/p1.jpg');
      expect(backend.storage.keys, ['ride-media/me/rides-1/p1.jpg']);
      expect(LocalRideStore.debugMedia, isEmpty);
      final stored = (await LocalRideStore().loadAll()).single;
      expect(stored.media.single.uploaded, isTrue);

      // Not again.
      await RideSyncService().syncPending();
      await _arrive(tester);
      expect(backend.tables['ride_media'], hasLength(1));
    });
  });

  group('ride page', () {
    testWidgets('shows the rider\'s words and its flag; they can delete it',
        (tester) async {
      backend.tables['rides'] = [
        Fixtures.ride()
          ..['journal'] = 'Fog lifting off the hills.'
          ..['flag_lat'] = 27.71
          ..['flag_lng'] = 85.52,
      ];
      backend.tables['ride_media'] = [];
      final item = FeedItem.fromJson(backend.tables['rides']!.single);
      expect(item.flag, (lat: 27.71, lng: 85.52));
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(withProviders(MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => RideDetailScreen(item: item))),
            child: const Text('open'),
          ),
        ),
      )));
      await tester.tap(find.text('open'));
      await _arrive(tester);
      await _settle(tester);

      expect(find.text('Fog lifting off the hills.'), findsOneWidget);
      expect(find.text('Nagarkot sunrise run'), findsWidgets);

      await tester.tap(find.byTooltip('More'));
      await _settle(tester);
      await tester.tap(find.text('Delete ride'));
      await _settle(tester);
      await tester.tap(find.text('Delete'));
      await _arrive(tester);
      await _settle(tester);
      expect(backend.tables['rides'], isEmpty);
      expect(find.byType(RideDetailScreen), findsNothing);
    });
  });

  group('ride card', () {
    final jpeg = Uint8List.fromList([0xFF, 0xD8, 1, 2, 3, 0xFF, 0xD9]);

    testWidgets('is uploaded and linked on the ride', (tester) async {
      final ride = _finished();
      final saving = RideRepository().saveRide(ride, card: jpeg);
      await _arrive(tester);
      final saved = await saving;

      expect(saved.synced, isTrue);
      expect(saved.hasCard, isTrue);
      expect(backend.storage.keys, ['ride-cards/me/ride-1.jpg']);
      expect(
          backend.tables['rides']!.single['card_image_url'],
          startsWith('https://fake.supabase.co/storage/v1/object/public/'
              'ride-cards/me/ride-1.jpg'));
      // Uploaded, so the phone's copy is gone.
      expect(LocalRideStore.debugCards, isEmpty);
    });

    testWidgets('one the server refuses doesn\'t hold the ride back',
        (tester) async {
      backend.storageError = 413;
      final saving = RideRepository().saveRide(_finished(), card: jpeg);
      await _arrive(tester);
      final saved = await saving;

      expect(saved.synced, isTrue);
      expect(backend.tables['rides']!.single.containsKey('card_image_url'),
          isFalse);
    });

    testWidgets('offline, waits on the phone with its ride, then syncs',
        (tester) async {
      backend.offline = true;
      final saving = RideRepository().saveRide(_finished(), card: jpeg);
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(seconds: 1)); // request retries
      }
      final saved = await saving;
      expect(saved.synced, isFalse);
      expect(LocalRideStore.debugCards.keys, ['ride-1']);
      expect((await LocalRideStore().pendingUnsynced()).single.hasCard, isTrue);

      backend.offline = false;
      final syncing = RideSyncService().syncPending();
      await _arrive(tester);
      expect(await syncing, 1);
      expect(backend.storage.keys, ['ride-cards/me/ride-1.jpg']);
      expect(backend.tables['rides']!.single['card_image_url'],
          contains('/ride-cards/me/ride-1.jpg'));
      expect(LocalRideStore.debugCards, isEmpty);
    });

    testWidgets('shows on the ride\'s page, below the map and stats',
        (tester) async {
      const url = 'https://example.com/card.jpg';
      final item = FeedItem.fromJson(Fixtures.ride(cardImageUrl: url));
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
          withProviders(MaterialApp(home: RideDetailScreen(item: item))));
      await tester.pump();

      final card = find.byWidgetPredicate(
          (w) => w is NetworkPhoto && w.url == url,
          description: 'ride card image',
          skipOffstage: false);
      expect(card, findsOneWidget);
      await tester.ensureVisible(card); // first in the photos row
      await tester.pump();
      expect(tester.getTopLeft(card).dy,
          greaterThan(tester.getBottomLeft(find.text('M CLIMBED')).dy));
      // 4:5, like the image.
      final size = tester.getSize(card);
      expect(size.width / size.height, closeTo(0.8, 0.01));
    });

    testWidgets('rides without one show no card', (tester) async {
      final item = FeedItem.fromJson(Fixtures.ride());
      await tester.pumpWidget(
          withProviders(MaterialApp(home: RideDetailScreen(item: item))));
      await tester.pump();
      expect(find.byType(NetworkPhoto), findsNothing);
    });
  });
}
