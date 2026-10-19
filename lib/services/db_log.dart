// ignore_for_file: avoid_print

import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Debug builds only: prints what is about to be written to the database,
/// as the JSON that goes over the wire, with its size.
///
/// Long payloads (a ride's track) are printed in pieces, since logcat cuts
/// a line off at about 4 KB.
void logDbWrite(String what, Object? payload) {
  if (!kDebugMode) return;
  final json = jsonEncode(payload);
  final bytes = utf8.encode(json).length;
  print('[DB] $what — ${formatBytes(bytes)} ($bytes bytes)');
  const chunk = 800;
  for (var i = 0; i < json.length; i += chunk) {
    final end = i + chunk < json.length ? i + chunk : json.length;
    print('[DB]   ${json.substring(i, end)}');
  }
}

/// Debug builds only: prints a file about to be uploaded to storage.
void logStorageUpload(
    String bucket, String path, Uint8List bytes, String contentType) {
  if (!kDebugMode) return;
  print('[DB] storage $bucket/$path ($contentType) — '
      '${formatBytes(bytes.length)} (${bytes.length} bytes)');
}

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
}
