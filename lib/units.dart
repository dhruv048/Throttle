/// Distances and speeds the way the rider reads them: kilometres (km/h)
/// or miles (mph). Everything is stored in km; only what's shown changes.
library;

import 'package:flutter/widgets.dart';

import 'format.dart';

enum Units {
  metric('km', 'km/h', 1),
  imperial('mi', 'mph', 0.621371192);

  const Units(this.distanceUnit, this.speedUnit, this._perKm);

  /// "km" or "mi".
  final String distanceUnit;

  /// "km/h" or "mph".
  final String speedUnit;
  final double _perKm;

  /// [km] in this rider's units.
  double distance(double km) => km * _perKm;

  /// [kmh] in this rider's units.
  double speed(double kmh) => kmh * _perKm;

  /// "50 km/h", "31 mph".
  String speedText(double kmh) => '${speed(kmh).round()} $speedUnit';

  /// The number alone: "22.4" (whole numbers from 100 up), in these units.
  String short(double km) => formatKm(distance(km));

  /// "22.4 km", "13.9 mi".
  String shortText(double km) => '${short(km)} $distanceUnit';

  /// Exact, for totals: "1,234.5".
  String total(double km) => formatDistance(distance(km));

  /// "1,234.5 km".
  String totalText(double km) => '${total(km)} $distanceUnit';

  /// [km] to [decimals] places, in these units: "22.40".
  String fixed(double km, int decimals) =>
      distance(km).toStringAsFixed(decimals);

  static Units fromName(String? name) =>
      Units.values.where((u) => u.name == name).firstOrNull ?? Units.metric;
}

/// The rider's units, for everything below it. Without one (e.g. a widget
/// shown on its own), kilometres.
class UnitsScope extends InheritedWidget {
  const UnitsScope({super.key, required this.units, required super.child});

  final Units units;

  static Units of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<UnitsScope>()?.units ??
      Units.metric;

  @override
  bool updateShouldNotify(UnitsScope old) => old.units != units;
}

extension UnitsOfContext on BuildContext {
  /// The rider's units (see [UnitsScope]).
  Units get units => UnitsScope.of(this);
}
