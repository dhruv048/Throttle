import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// An in-memory stand-in for the Supabase REST API, wired into the real
/// `Supabase.instance` client, so screens run unmodified against fixtures.
///
/// - [tables] holds rows per table; GET/HEAD apply simple `eq`, `neq` and
///   `in` filters (ordering and other operators are ignored, so fixtures
///   should already be in the order the screen expects).
/// - Set [hold] to keep every request waiting until [release], to see what a
///   screen shows while it loads.
/// - Inserts that ask for the new row back get it (with a generated `id`).
/// - Storage uploads land in [storage]; set [storageError] to refuse them.
/// - Set [offline] to fail every request like a dropped connection.
class FakeSupabase {
  FakeSupabase._();

  static final instance = FakeSupabase._();
  static bool _initialized = false;

  final Map<String, List<Map<String, dynamic>>> tables = {};
  final List<http.Request> requests = [];

  /// Uploaded files by `<bucket>/<path>`.
  final Map<String, List<int>> storage = {};
  int? storageError;
  bool offline = false;

  /// Columns the server doesn't have (a migration not applied): asking for
  /// one fails like PostgREST does.
  final Set<String> missingColumns = {};
  bool hold = false;
  final List<Completer<void>> _held = [];

  /// Initialises Supabase once per test file, signed in as [userId].
  static Future<FakeSupabase> start({String userId = 'me'}) async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final fake = instance;
    if (!_initialized) {
      await Supabase.initialize(
        url: 'https://fake.supabase.co',
        publishableKey: 'anon',
        httpClient: MockClient(fake._handle),
        authOptions: FlutterAuthClientOptions(
          localStorage: const EmptyLocalStorage(),
          pkceAsyncStorage: _MemoryStorage(),
          detectSessionInUri: false,
          autoRefreshToken: false,
        ),
        debug: false,
      );
      _initialized = true;
    }
    await Supabase.instance.client.auth.recoverSession(_sessionJson(userId));
    return fake;
  }

  void reset() {
    tables.clear();
    requests.clear();
    storage.clear();
    storageError = null;
    offline = false;
    missingColumns.clear();
    release();
  }

  /// Lets every held request (and later ones) through.
  void release() {
    hold = false;
    for (final c in _held) {
      if (!c.isCompleted) c.complete();
    }
    _held.clear();
  }

  Iterable<http.Request> writes(String table) => requests.where(
        (r) =>
            r.method != 'GET' &&
            r.method != 'HEAD' &&
            r.url.pathSegments.last == table,
      );

  Future<http.Response> _handle(http.Request req) async {
    requests.add(req);
    if (hold) {
      final gate = Completer<void>();
      _held.add(gate);
      await gate.future;
    }
    if (offline) throw http.ClientException('offline', req.url);
    final segments = req.url.pathSegments;
    if (segments.length >= 4 && segments[0] == 'storage') return _storage(req);
    if (segments.length < 3 || segments[0] != 'rest') {
      return http.Response('{}', 200, headers: _json, request: req);
    }
    // Database functions answer with the rows in tables['rpc/<name>'].
    if (segments.length >= 4 && segments[2] == 'rpc') {
      return http.Response(jsonEncode(tables['rpc/${segments[3]}'] ?? []), 200,
          headers: _json, request: req);
    }
    final table = tables.putIfAbsent(segments[2], () => []);
    var rows = _filter(table, req.url.queryParameters);
    switch (req.method) {
      case 'HEAD':
        return http.Response('', 200,
            headers: {
              'content-range':
                  rows.isEmpty ? '*/0' : '0-${rows.length - 1}/${rows.length}',
            },
            request: req);
      case 'GET':
        final select = req.url.queryParameters['select'] ?? '*';
        final missing = missingColumns
            .where((c) => RegExp('\\b$c\\b').hasMatch(select))
            .firstOrNull;
        if (missing != null) {
          return http.Response(
              jsonEncode({
                'code': '42703',
                'message': 'column $missing does not exist',
              }),
              400,
              headers: _json,
              request: req);
        }
        rows = [for (final r in rows) _embedded(r, select)];
        // .single() / .maybeSingle() ask for one object.
        if (req.headers['Accept']?.contains('vnd.pgrst.object') ?? false) {
          if (rows.length != 1) {
            return http.Response(
                jsonEncode({
                  'code': 'PGRST116',
                  'message': 'JSON object requested, ${rows.length} rows',
                }),
                406,
                headers: _json,
                request: req);
          }
          return http.Response(jsonEncode(rows.single), 200,
              headers: _json, request: req);
        }
        return http.Response(jsonEncode(rows), 200,
            headers: _json, request: req);
      case 'POST':
        final body = jsonDecode(req.body);
        final prefer = req.headers['Prefer'] ?? '';
        final represent = prefer.contains('return=representation');
        // Upserts name the columns that make a row the same row.
        final onConflict = req.url.queryParameters['on_conflict']?.split(',');
        final inserted = <Map<String, dynamic>>[];
        for (final row in body is List ? body : [body]) {
          final r = Map<String, dynamic>.from(row as Map);
          if (onConflict != null) {
            final same = table
                .where((t) => onConflict.every((c) => '${t[c]}' == '${r[c]}'))
                .firstOrNull;
            if (same != null) {
              if (!prefer.contains('ignore-duplicates')) same.addAll(r);
              inserted.add(same);
              continue;
            }
          } else if (_violatesUnique(segments[2], table, r)) {
            return http.Response(
                jsonEncode({
                  'code': '23505',
                  'message': 'duplicate key value violates unique constraint',
                }),
                409,
                headers: _json,
                request: req);
          }
          if (represent) {
            r.putIfAbsent('id', () => '${segments[2]}-${table.length + 1}');
          }
          table.add(r);
          inserted.add(r);
        }
        if (!represent) return http.Response('', 201, request: req);
        final single =
            req.headers['Accept']?.contains('vnd.pgrst.object') ?? false;
        return http.Response(
            jsonEncode(single ? inserted.first : inserted), 201,
            headers: _json, request: req);
      case 'PATCH':
        final changes = Map<String, dynamic>.from(jsonDecode(req.body) as Map);
        for (final row in rows) {
          row.addAll(changes);
        }
        final represent =
            req.headers['Prefer']?.contains('return=representation') ?? false;
        if (!represent) return http.Response('', 204, request: req);
        final single =
            req.headers['Accept']?.contains('vnd.pgrst.object') ?? false;
        return http.Response(jsonEncode(single ? rows.firstOrNull : rows), 200,
            headers: _json, request: req);
      case 'DELETE':
        table.removeWhere(rows.contains);
        return http.Response('', 204, request: req);
      default:
        return http.Response('', 400, request: req);
    }
  }

  static const _json = {'content-type': 'application/json; charset=utf-8'};

  /// [row] with each embedded resource the select names
  /// (`alias:table(a, b)`) cut down to the columns asked for, as PostgREST
  /// returns them. Fixtures hold every column.
  static Map<String, dynamic> _embedded(
      Map<String, dynamic> row, String select) {
    var out = row;
    for (final m in RegExp(r'(\w+):\w+\(([^)]*)\)').allMatches(select)) {
      final alias = m.group(1)!;
      final columns = m.group(2)!.split(',').map((c) => c.trim()).toList();
      final embedded = row[alias];
      if (embedded is! Map || columns.contains('*')) continue;
      out = {
        ...out,
        alias: {for (final c in columns) c: embedded[c]},
      };
    }
    return out;
  }

  /// The schema's unique keys the app relies on.
  static const _unique = {
    'rides': [
      ['user_id', 'local_id'],
    ],
    'ride_tracks': [
      ['ride_id'],
    ],
    'ride_media': [
      ['storage_path'],
    ],
  };

  static bool _violatesUnique(String table, List<Map<String, dynamic>> rows,
          Map<String, dynamic> row) =>
      (_unique[table] ?? const []).any((key) =>
          key.every((c) => row[c] != null) &&
          rows.any((r) => key.every((c) => '${r[c]}' == '${row[c]}')));

  /// `/storage/v1/object/<bucket>/<path>`: upload (POST/PUT) or, with no
  /// path, remove (DELETE with `{"prefixes": [...]}`).
  http.Response _storage(http.Request req) {
    final segments = req.url.pathSegments;
    final bucket = segments[3];
    switch (req.method) {
      case 'POST' || 'PUT':
        if (storageError != null) {
          return http.Response(
              jsonEncode({
                'statusCode': '$storageError',
                'error': 'Refused',
                'message': 'Refused by the test',
              }),
              storageError!,
              headers: _json,
              request: req);
        }
        final key = segments.skip(3).join('/');
        storage[key] = req.bodyBytes;
        return http.Response(jsonEncode({'Key': key, 'Id': key}), 200,
            headers: _json, request: req);
      case 'DELETE':
        final paths = (jsonDecode(req.body) as Map)['prefixes'] as List;
        for (final path in paths) {
          storage.remove('$bucket/$path');
        }
        return http.Response('[]', 200, headers: _json, request: req);
      default:
        return http.Response('{}', 200, headers: _json, request: req);
    }
  }

  static List<Map<String, dynamic>> _filter(
    List<Map<String, dynamic>> rows,
    Map<String, String> params,
  ) {
    var out = rows;
    params.forEach((column, expr) {
      bool keep(Map<String, dynamic> row) {
        final value = '${row[column]}';
        if (expr == 'is.null') return row[column] == null;
        if (expr.startsWith('eq.')) return value == expr.substring(3);
        if (expr.startsWith('neq.')) return value != expr.substring(4);
        if (expr.startsWith('in.(')) {
          final list = expr
              .substring(4, expr.length - 1)
              .split(',')
              .map((s) => s.replaceAll('"', ''));
          return list.contains(value);
        }
        return true; // select, order, limit, gte, or, offset … ignored
      }

      out = out.where(keep).toList();
    });
    return out;
  }

  static String _sessionJson(String userId) {
    String b64(Map<String, dynamic> m) =>
        base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
    final exp =
        DateTime.now().add(const Duration(days: 1)).millisecondsSinceEpoch ~/
            1000;
    final jwt = '${b64({'alg': 'HS256', 'typ': 'JWT'})}.'
        '${b64({
          'sub': userId,
          'exp': exp,
          'role': 'authenticated',
          'aud': 'authenticated'
        })}.sig';
    return jsonEncode({
      'access_token': jwt,
      'token_type': 'bearer',
      'expires_in': 86400,
      'refresh_token': 'refresh',
      'user': {
        'id': userId,
        'aud': 'authenticated',
        'app_metadata': <String, dynamic>{},
        'user_metadata': <String, dynamic>{},
        'created_at': '2026-01-01T00:00:00Z',
      },
    });
  }
}

class _MemoryStorage extends GotrueAsyncStorage {
  final _items = <String, String>{};

  @override
  Future<String?> getItem({required String key}) async => _items[key];

  @override
  Future<void> setItem({required String key, required String value}) async =>
      _items[key] = value;

  @override
  Future<void> removeItem({required String key}) async => _items.remove(key);
}

/// Fixture rows shaped like the app's queries return them.
class Fixtures {
  /// A `notifications` row with its embedded `actor` and `ride`.
  static Map<String, dynamic> notification({
    required String id,
    String kind = 'kudos',
    String actorId = 'mira',
    String actorName = 'Mira Rai',
    String? rideId = 'r1',
    String? rideTitle = 'Nagarkot sunrise run',
    bool read = false,
    Duration ago = const Duration(minutes: 5),
  }) =>
      {
        'id': id,
        'user_id': 'me',
        'actor_id': actorId,
        'kind': kind,
        'ride_id': kind == 'kudos' ? rideId : null,
        'created_at': DateTime.now().subtract(ago).toUtc().toIso8601String(),
        'read_at': read ? '2026-10-01T00:00:00Z' : null,
        'actor': profile(
            id: actorId,
            username: actorName.toLowerCase().replaceAll(' ', '_'),
            displayName: actorName),
        'ride': kind == 'kudos' && rideId != null
            ? {'id': rideId, 'title': rideTitle}
            : null,
      };

  static Map<String, dynamic> profile({
    String id = 'me',
    String username = 'priya_g',
    String displayName = 'Priya Gurung',
    String? city = 'Bhaktapur',
  }) =>
      {
        'id': id,
        'username': username,
        'display_name': displayName,
        'city': city,
        'onboarding_completed': true,
      };

  static Map<String, dynamic> bike({
    String id = 'b1',
    String userId = 'me',
    String name = 'KTM 390 Duke',
    bool primary = true,
    double riddenKm = 412.3,
    String? photoUrl,
  }) =>
      {
        'id': id,
        'user_id': userId,
        'name': name,
        'is_primary': primary,
        'odometer_km': riddenKm,
        'ridden_km': riddenKm,
        'photo_url': photoUrl,
      };

  /// A `rides` row with the feed's embedded rider/bike/track.
  static Map<String, dynamic> ride({
    String id = 'r1',
    String userId = 'me',
    String title = 'Nagarkot sunrise run',
    double km = 22.4,
    int kudos = 4,
    String visibility = 'public',
    DateTime? startedAt,
    String? cardImageUrl,
  }) =>
      {
        'id': id,
        'user_id': userId,
        'title': title,
        'visibility': visibility,
        'distance_km': km,
        'moving_time_secs': 3120,
        'avg_speed_kmh': 25.8,
        'max_speed_kmh': 64,
        'elevation_m': 700,
        'kudos_count': kudos,
        'comments_count': 1,
        'started_at':
            (startedAt ?? DateTime.now().subtract(const Duration(hours: 2)))
                .toUtc()
                .toIso8601String(),
        'card_image_url': cardImageUrl,
        'rider': profile(id: userId),
        'bike': {'name': 'KTM 390 Duke', 'photo_url': null},
        'track': {
          'points': [
            {'lat': 27.67, 'lng': 85.42},
            {'lat': 27.71, 'lng': 85.52},
          ],
          // As the server makes it (20261018000000_track_previews.sql).
          'preview': {
            'v': 2,
            'p': [
              [27.67, 85.42],
              [27.71, 85.52],
            ],
          },
        },
      };
}
