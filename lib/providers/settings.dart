import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../units.dart';

/// Km or miles, as the rider picked in Profile. Kept on this phone.
final unitsProvider = NotifierProvider<UnitsSetting, Units>(UnitsSetting.new);

class UnitsSetting extends Notifier<Units> {
  static const _key = 'units';

  @override
  Units build() {
    _load();
    return Units.metric;
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = Units.fromName(prefs.getString(_key));
      if (ref.mounted) state = saved;
    } catch (e) {
      debugPrint('Couldn\'t read the units setting: $e');
    }
  }

  Future<void> set(Units units) async {
    state = units;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, units.name);
    } catch (e) {
      debugPrint('Couldn\'t save the units setting: $e');
    }
  }
}
