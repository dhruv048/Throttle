import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart' show XFile;
import 'package:throttle/models/models.dart';
import 'package:throttle/providers/core.dart';
import 'package:throttle/providers/journal.dart';
import 'package:throttle/screens/ride_detail_screen.dart';
import 'package:throttle/screens/ride_journal_screen.dart';
import 'package:throttle/services/local_ride_store.dart';
import 'package:throttle/services/media_placement.dart';
import 'package:throttle/widgets/map_tiles.dart';

import 'support/fake_gps.dart';
import 'support/fake_supabase.dart';

late FakeSupabase backend;

/// A ride north from Bhaktapur, a point every 100 m, a minute apart.
final _start = DateTime.utc(2026, 10, 9, 1, 0);
final _track = [
  for (var i = 0; i <= 50; i++)
    TrackPoint(
      lat: 27.67 + i * 100 / 111320,
      lng: 85.42,
      t: _start.add(Duration(minutes: i)),
    ),
];

/// A small JPEG, with the GPS position and capture time a phone camera
/// writes when given.
Uint8List _jpeg({double? lat, double? lng, String? taken, String? offset}) {
  final image = img.Image(width: 8, height: 8);
  if (lat != null && lng != null) {
    img.IfdValueRational dms(double v) {
      final d = v.abs().floor();
      final m = ((v.abs() - d) * 60).floor();
      final s = ((v.abs() - d - m / 60) * 3600 * 1000).round();
      // Degrees, minutes, seconds, as cameras write them.
      return img.IfdValueRational(d, 1)
        ..value.add(img.IfdValueRational(m, 1).value.single)
        ..value.add(img.IfdValueRational(s, 1000).value.single);
    }

    image.exif.gpsIfd.data[0x0001] = img.IfdValueAscii(lat < 0 ? 'S' : 'N');
    image.exif.gpsIfd.data[0x0002] = dms(lat);
    image.exif.gpsIfd.data[0x0003] = img.IfdValueAscii(lng < 0 ? 'W' : 'E');
    image.exif.gpsIfd.data[0x0004] = dms(lng);
  }
  if (taken != null) {
    image.exif.exifIfd.data[0x9003] = img.IfdValueAscii(taken);
    if (offset != null) {
      image.exif.exifIfd.data[0x9011] = img.IfdValueAscii(offset);
    }
  }
  return img.encodeJpg(image);
}

FeedItem _ride({String userId = 'me'}) => FeedItem(
      ride: RideRecord(
        id: 'r1',
        userId: userId,
        title: 'Nagarkot sunrise run',
        visibility: RideVisibility.public,
        distanceKm: 5,
        movingTimeSecs: 3000,
        avgSpeedKmh: 6,
        maxSpeedKmh: 42,
        startedAt: _start,
      ),
      rider: Profile(
          id: userId, displayName: userId == 'me' ? 'Priya Gurung' : 'Mira'),
      points: _track,
    );

Future<void> _arrive(WidgetTester tester) async {
  backend.release();
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Lets a sheet or dialog animate in or out.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _pumpJournal(WidgetTester tester,
    {FeedItem? item, List<XFile> picked = const []}) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    retry: noRetry,
    overrides: [
      pickJournalMediaProvider.overrideWithValue(() async => picked),
    ],
    child: MaterialApp(home: RideJournalScreen(item: item ?? _ride())),
  ));
  await _arrive(tester);
}

Map<String, dynamic> _media(String id,
        {double? lat, double? lng, String? caption, String kind = 'photo'}) =>
    {
      'id': id,
      'ride_id': 'r1',
      'user_id': 'me',
      'kind': kind,
      'url': 'https://example.com/$id.jpg',
      'storage_path': 'me/r1/$id.jpg',
      'caption': caption,
      'lat': lat,
      'lng': lng,
    };

void main() {
  group('placing photos on the route', () {
    test('reads where and when a photo was taken', () {
      final meta = readPhotoMeta(_jpeg(
          lat: 27.712345,
          lng: -85.4321,
          taken: '2026:10:09 06:52:10',
          offset: '+05:45'));
      expect(meta.lat, closeTo(27.712345, 1e-5));
      expect(meta.lng, closeTo(-85.4321, 1e-5));
      expect(meta.takenAt, DateTime.utc(2026, 10, 9, 1, 7, 10));
    });

    test('photos without metadata say nothing', () {
      final meta = readPhotoMeta(_jpeg());
      expect(meta.hasLocation, isFalse);
      expect(meta.takenAt, isNull);
      expect(readPhotoMeta(Uint8List.fromList([1, 2, 3])).hasLocation, isFalse);
    });

    test('by where it was taken, else when, else not at all', () {
      // Taken 30 m off the route, near its 20th point.
      final near = placeOnRoute(_track,
          lat: _track[20].lat, lng: _track[20].lng + 30 / 98500);
      expect(near!.index, 20);
      expect(near.by, PlacedBy.location);

      // Taken far from the route, but during the ride.
      final during = placeOnRoute(_track,
          lat: 28.5,
          lng: 84,
          takenAt: _start.add(const Duration(minutes: 33, seconds: 20)));
      expect(during!.index, 33);
      expect(during.by, PlacedBy.time);

      expect(
          placeOnRoute(_track,
              takenAt: _start.subtract(const Duration(hours: 2))),
          isNull);
      expect(placeOnRoute(_track), isNull);
    });

    test('distance along the route', () {
      final km = distanceAlongKm(_track);
      expect(km.first, 0);
      expect(km[10], closeTo(1.0, 0.01));
      expect(km.last, closeTo(5.0, 0.01));
    });
  });

  group('Ride Journal', () {
    setUpAll(() async {
      backend = await FakeSupabase.start(userId: 'me');
      MapTiles.debugProvider = BlankTiles();
    });

    setUp(() {
      LocalRideStore.debugReset();
      backend.reset();
      backend.tables
        ..['rides'] = [
          {'id': 'r1', 'user_id': 'me', 'journal': null},
        ]
        ..['ride_media'] = [];
    });

    testWidgets('photos and videos go where they were taken on the route',
        (tester) async {
      await _pumpJournal(tester, picked: [
        XFile.fromData(_jpeg(lat: _track[30].lat, lng: _track[30].lng),
            path: '/picked/IMG_0001.jpg'),
        XFile.fromData(_jpeg(), path: '/picked/screenshot.png'),
        XFile.fromData(Uint8List.fromList([0, 0, 0, 1]),
            path: '/picked/clip.MOV'),
        XFile.fromData(Uint8List.fromList([1]), path: '/picked/notes.pdf'),
      ]);
      expect(find.text('Nagarkot sunrise run'), findsOneWidget);

      await tester.tap(find.text('ADD PHOTOS & VIDEOS'));
      await _arrive(tester);

      final rows = backend.tables['ride_media']!;
      expect(rows, hasLength(3)); // not the PDF
      expect(rows[0]['kind'], 'photo');
      expect(rows[0]['lat'], closeTo(_track[30].lat, 1e-9));
      expect(rows[1]['lat'], isNull); // nothing says where
      expect(rows[2]['kind'], 'video');
      expect(backend.storage.keys.map((k) => k.split('.').last).toList(),
          ['jpg', 'png', 'mov']);
      expect(
          backend.storage.keys.every((k) => k.startsWith('ride-media/me/r1/')),
          isTrue);

      expect(find.text('ALONG THE ROUTE'), findsOneWidget);
      final at = _track[30].t!.toLocal(); // the photo's own time isn't known
      String two(int n) => n.toString().padLeft(2, '0');
      expect(find.text('3.0 km in · ${two(at.hour)}:${two(at.minute)}'),
          findsOneWidget);
      await tester.scrollUntilVisible(find.text('NOT ON THE ROUTE YET'), 300);
      expect(find.textContaining('2 don\'t say where they were taken'),
          findsOneWidget);
      expect(find.textContaining('1 skipped'), findsOneWidget);
    });

    testWidgets('memories and captions', (tester) async {
      backend.tables['ride_media'] = [
        _media('m1', lat: _track[10].lat, lng: _track[10].lng),
      ];
      await _pumpJournal(tester);

      await tester.tap(find.text('Write'));
      await _settle(tester);
      await tester.enterText(
          find.byType(TextField), 'Fog lifting off the hills.');
      await tester.tap(find.text('SAVE'));
      await _arrive(tester);
      await _settle(tester);
      expect(backend.tables['rides']!.single['journal'],
          'Fog lifting off the hills.');
      expect(find.text('Fog lifting off the hills.'), findsOneWidget);

      await tester.ensureVisible(find.text('Add a caption'));
      await tester.pump();
      await tester.tap(find.text('Add a caption'));
      await _settle(tester);
      await tester.enterText(find.byType(TextField), 'Tea stop');
      await tester.tap(find.text('SAVE'));
      await _arrive(tester);
      await _settle(tester);
      expect(backend.tables['ride_media']!.single['caption'], 'Tea stop');
      expect(find.text('Tea stop'), findsOneWidget);
    });

    testWidgets('one without a place can be put on the route, or removed',
        (tester) async {
      backend.tables['ride_media'] = [_media('m1')];
      backend.storage['ride-media/me/r1/m1.jpg'] = [1];
      await _pumpJournal(tester);

      await tester.ensureVisible(find.text('Place on route'));
      await tester.pump();
      await tester.tap(find.text('Place on route'));
      await _settle(tester);
      expect(find.text('Where was this?'), findsOneWidget);
      expect(find.text('5.0 km in'), findsOneWidget); // starts at the end
      await tester.tap(find.text('PUT IT HERE'));
      await _arrive(tester);
      await _settle(tester);
      expect(backend.tables['ride_media']!.single['lat'],
          closeTo(_track.last.lat, 1e-9));
      expect(find.text('ALONG THE ROUTE'), findsOneWidget);

      await tester.tap(find.byTooltip('Options'));
      await _settle(tester);
      await tester.tap(find.text('Remove'));
      await _settle(tester);
      await tester.tap(find.text('Remove').last); // confirm
      await _arrive(tester);
      await _settle(tester);
      expect(backend.tables['ride_media'], isEmpty);
      expect(backend.storage, isEmpty);
    });

    testWidgets('other riders read it, but can\'t change it', (tester) async {
      backend.tables['rides'] = [
        {'id': 'r1', 'user_id': 'mira', 'journal': 'Best ride of the year.'},
      ];
      backend.tables['ride_media'] = [
        _media('m1', lat: _track[5].lat, lng: _track[5].lng, caption: 'Dawn'),
      ];
      await _pumpJournal(tester, item: _ride(userId: 'mira'));
      expect(find.text('Best ride of the year.'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Dawn'), 300);
      expect(find.text('ADD PHOTOS & VIDEOS'), findsNothing);
      expect(find.text('Write'), findsNothing);
      expect(find.text('Edit'), findsNothing);
      expect(find.byTooltip('Options'), findsNothing);
    });

    testWidgets('the ride\'s page previews it and pins its photos on the map',
        (tester) async {
      backend.tables['rides'] = [
        {'id': 'r1', 'user_id': 'me', 'journal': 'Fog lifting off the hills.'},
      ];
      backend.tables['ride_media'] = [
        _media('m1', lat: _track[5].lat, lng: _track[5].lng),
        _media('m2', lat: _track[40].lat, lng: _track[40].lng),
        _media('m3', kind: 'video'),
      ];
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        retry: noRetry,
        child: MaterialApp(home: RideDetailScreen(item: _ride())),
      ));
      await _arrive(tester);

      expect(find.byIcon(Icons.photo_camera), findsNWidgets(2)); // placed
      await tester.scrollUntilVisible(find.text('RIDE JOURNAL'), 300,
          scrollable: find.byType(Scrollable).first);
      expect(find.text('2 photos · 1 video'), findsOneWidget);
      expect(find.text('Fog lifting off the hills.'), findsOneWidget);

      await tester.tap(find.text('RIDE JOURNAL'));
      await _arrive(tester);
      await _settle(tester);
      expect(find.byType(RideJournalScreen), findsOneWidget);
    });
  });
}
