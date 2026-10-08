import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/models.dart';

class LocalRideStore {
  static const _fileName = 'pending_rides.json';

  // Every mutation is read-modify-write on one file; chain them so a share
  // and a background sync can't overwrite each other's changes.
  static Future<void> _tail = Future.value();

  static Future<T> _serialized<T>(Future<T> Function() op) {
    final result = _tail.then((_) => op());
    _tail = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  Future<List<PendingRide>> loadAll() async {
    try {
      final file = await _file();
      if (!await file.exists()) return [];
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return [];
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => PendingRide.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveAll(List<PendingRide> rides) async {
    final file = await _file();
    final encoded = jsonEncode(rides.map((r) => r.toJson()).toList());
    await file.writeAsString(encoded, flush: true);
  }

  Future<PendingRide> enqueue(PendingRide ride) => _serialized(() async {
        final all = await loadAll();
        all.insert(0, ride);
        await saveAll(all);
        return ride;
      });

  Future<void> markSynced(String localId, String remoteId) =>
      _serialized(() async {
        final all = await loadAll();
        for (final r in all) {
          if (r.localId == localId) {
            r.synced = true;
            r.remoteId = remoteId;
          }
        }
        await saveAll(all);
      });

  Future<List<PendingRide>> pendingUnsynced() async {
    final all = await loadAll();
    return all.where((r) => !r.synced).toList();
  }

  Future<void> remove(String localId) => _serialized(() async {
        final all = await loadAll();
        all.removeWhere((r) => r.localId == localId);
        await saveAll(all);
      });
}
