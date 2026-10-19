/// Display formatting shared across screens.
library;

String formatNumber(int n) {
  final s = n.toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    final fromEnd = s.length - i;
    buf.write(s[i]);
    if (fromEnd > 1 && fromEnd % 3 == 1) buf.write(',');
  }
  return buf.toString();
}

/// Exact distance for totals: one decimal, thousands separated ("1,234.5").
String formatDistance(double km) {
  final tenths = (km * 10).round();
  return '${formatNumber(tenths ~/ 10)}.${tenths % 10}';
}

String formatKm(double km) =>
    km >= 100 ? km.round().toString() : km.toStringAsFixed(1);

String formatDuration(int secs) {
  final h = secs ~/ 3600;
  final m = (secs % 3600) ~/ 60;
  return h > 0 ? '${h}h ${m}m' : '${m}m';
}

String timeAgo(DateTime t, {DateTime? now}) {
  final d = (now ?? DateTime.now()).difference(t);
  if (d.inMinutes < 1) return 'Just now';
  if (d.inMinutes < 60) return '${d.inMinutes}m ago';
  if (d.inHours < 24) return '${d.inHours}h ago';
  if (d.inDays == 1) return 'Yesterday';
  if (d.inDays < 7) return '${d.inDays}d ago';
  return '${t.day}/${t.month}/${t.year}';
}
