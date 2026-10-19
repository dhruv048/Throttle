import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:throttle/widgets/live_ride_map.dart';
import 'package:throttle/widgets/map_tiles.dart';

import 'support/fake_gps.dart';

void main() {
  setUp(() => MapTiles.debugProvider = BlankTiles());
  tearDown(() => MapTiles.debugProvider = null);

  const a = LatLng(27.7, 85.3);
  const b = LatLng(27.7 + 20 / 111320, 85.3); // 20 m north

  Widget map(LatLng here, List<LatLng> trail, {bool recording = true}) =>
      MaterialApp(
        home: LiveRideMap(
          here: here,
          accuracyM: 5,
          trail: trail,
          recording: recording,
        ),
      );

  LatLng dot(WidgetTester tester) =>
      tester.widget<MarkerLayer>(find.byType(MarkerLayer)).markers.single.point;

  List<List<LatLng>> lines(WidgetTester tester) => [
        for (final layer
            in tester.widgetList<PolylineLayer>(find.byType(PolylineLayer)))
          for (final line in layer.polylines) line.points,
      ];

  testWidgets('the dot glides to a new fix, and the trail follows it',
      (tester) async {
    await tester.pumpWidget(map(a, const [a]));
    await tester.pump();
    expect(dot(tester), a);

    await tester.pumpWidget(map(b, const [a, b]));
    await tester.pump(const Duration(milliseconds: 150));
    final mid = dot(tester);
    expect(mid.latitude, greaterThan(a.latitude));
    expect(mid.latitude, lessThan(b.latitude));
    // The line ends at the dot, not ahead of it at the new fix.
    for (final line in lines(tester)) {
      expect(line.last, isNot(b));
    }
    expect(lines(tester).any((line) => line.last == mid), isTrue);

    await tester.pumpAndSettle();
    expect(dot(tester), b);
    expect(lines(tester).any((line) => line.last == b), isTrue);
  });

  testWidgets('a far-off fix is jumped to', (tester) async {
    const far = LatLng(27.71, 85.3); // ~1.1 km
    await tester.pumpWidget(map(a, const []));
    await tester.pump();
    await tester.pumpWidget(map(far, const []));
    await tester.pump();
    expect(dot(tester), far);
  });

  testWidgets('while paused the trail stays where it was', (tester) async {
    await tester.pumpWidget(map(a, const [a], recording: false));
    await tester.pump();
    await tester.pumpWidget(map(b, const [a], recording: false));
    await tester.pumpAndSettle();
    expect(dot(tester), b);
    expect(lines(tester), isEmpty);
  });
}
