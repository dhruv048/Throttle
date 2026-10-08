import 'dart:ui';

class Ride {
  const Ride({
    required this.id,
    required this.rider,
    required this.initials,
    required this.ago,
    required this.title,
    required this.from,
    required this.to,
    required this.km,
    required this.duration,
    required this.elev,
    required this.kudos,
    required this.comments,
    required this.bike,
    required this.seed,
  });

  final String id;
  final String rider;
  final String initials;
  final String ago;
  final String title;
  final String from;
  final String to;
  final int km;
  final String duration;
  final int elev;
  final int kudos;
  final int comments;
  final String bike;
  final int seed;
}

class PopularRoute {
  const PopularRoute({
    required this.id,
    required this.name,
    required this.km,
    required this.time,
    required this.riders,
    required this.difficulty,
    required this.seed,
  });

  final String id;
  final String name;
  final int km;
  final String time;
  final int riders;
  final String difficulty;
  final int seed;
}

class NearbyRider {
  const NearbyRider({
    required this.name,
    required this.bike,
    required this.km,
    required this.initials,
  });

  final String name;
  final String bike;
  final String km;
  final String initials;
}

class Club {
  const Club({
    required this.name,
    required this.members,
    required this.initials,
  });

  final String name;
  final int members;
  final String initials;
}

class Bike {
  const Bike({
    required this.name,
    required this.year,
    required this.km,
    required this.primary,
  });

  final String name;
  final int year;
  final int km;
  final bool primary;
}

class Me {
  const Me({
    required this.name,
    required this.initials,
    required this.city,
    required this.followers,
    required this.following,
    required this.rides,
    required this.km,
    required this.elev,
    required this.hours,
    required this.bikes,
  });

  final String name;
  final String initials;
  final String city;
  final int followers;
  final int following;
  final int rides;
  final int km;
  final int elev;
  final int hours;
  final List<Bike> bikes;
}

class GroupRide {
  const GroupRide({
    required this.title,
    required this.when,
    required this.km,
    required this.riders,
    required this.spots,
    required this.meet,
  });

  final String title;
  final String when;
  final int km;
  final int riders;
  final int spots;
  final String meet;
}

const rides = [
  Ride(
    id: 'r1',
    rider: 'Alex Shrestha',
    initials: 'AS',
    ago: '2h ago',
    title: 'Namobuddha Sunday',
    from: 'Kathmandu',
    to: 'Namobuddha',
    km: 184,
    duration: '4h 12m',
    elev: 1840,
    kudos: 24,
    comments: 4,
    bike: 'Royal Enfield Himalayan',
    seed: 3,
  ),
  Ride(
    id: 'r2',
    rider: 'Priya Gurung',
    initials: 'PG',
    ago: '5h ago',
    title: 'Nagarkot sunrise run',
    from: 'Bhaktapur',
    to: 'Nagarkot',
    km: 62,
    duration: '1h 48m',
    elev: 1120,
    kudos: 41,
    comments: 9,
    bike: 'KTM 390 Duke',
    seed: 7,
  ),
  Ride(
    id: 'r3',
    rider: 'Kathmandu Riders Club',
    initials: 'KR',
    ago: 'Yesterday',
    title: 'Club ride · Kakani loop',
    from: 'Balaju',
    to: 'Kakani',
    km: 96,
    duration: '2h 55m',
    elev: 1310,
    kudos: 88,
    comments: 17,
    bike: '12 riders',
    seed: 11,
  ),
];

const routes = [
  PopularRoute(
    id: 'p1',
    name: 'Nagarkot Loop',
    km: 118,
    time: '3h 15m',
    riders: 324,
    difficulty: 'Twisty',
    seed: 5,
  ),
  PopularRoute(
    id: 'p2',
    name: 'Dhulikhel Ride',
    km: 86,
    time: '2h 20m',
    riders: 182,
    difficulty: 'Easy',
    seed: 9,
  ),
  PopularRoute(
    id: 'p3',
    name: 'Daman via Tribhuvan Rajpath',
    km: 142,
    time: '4h 40m',
    riders: 97,
    difficulty: 'Hairpins',
    seed: 13,
  ),
  PopularRoute(
    id: 'p4',
    name: 'Bandipur Escape',
    km: 143,
    time: '3h 50m',
    riders: 211,
    difficulty: 'Highway',
    seed: 2,
  ),
];

const riders = [
  NearbyRider(
      name: 'Sanjay Tamang',
      bike: 'Honda CB350',
      km: '8.2k km',
      initials: 'ST'),
  NearbyRider(
      name: 'Mira Rai', bike: 'Yamaha MT-15', km: '5.4k km', initials: 'MR'),
  NearbyRider(
      name: 'Bikash Lama',
      bike: 'BMW G 310 GS',
      km: '12.9k km',
      initials: 'BL'),
];

const clubs = [
  Club(name: 'Kathmandu Riders Club', members: 1240, initials: 'KR'),
  Club(name: 'Himalayan Adventure Tourers', members: 612, initials: 'HA'),
  Club(name: 'Valley Café Racers', members: 208, initials: 'VC'),
];

const groupRide = GroupRide(
  title: 'Saturday Morning Ride',
  when: 'Sat 07:00',
  km: 124,
  riders: 8,
  spots: 4,
  meet: 'Thamel Chowk',
);

const me = Me(
  name: 'Dhruv Karki',
  initials: 'DK',
  city: 'Kathmandu',
  followers: 312,
  following: 188,
  rides: 64,
  km: 7842,
  elev: 58210,
  hours: 211,
  bikes: [
    Bike(name: 'Yamaha MT-15', year: 2023, km: 5120, primary: true),
    Bike(name: 'Royal Enfield Himalayan', year: 2021, km: 2722, primary: false),
  ],
);

const weeklyKm = [120, 340, 80, 260, 410, 190, 520, 300];

/// Deterministic pseudo-random route path matching the React `routePath`.
List<Offset> routePoints(int seed, {double w = 320, double h = 120}) {
  var s = seed * 9301 + 49297;
  double rnd() {
    s = (s * 9301 + 49297) % 233280;
    return s / 233280;
  }

  const n = 9;
  return List.generate(n, (i) {
    return Offset(
      20 + (i * (w - 40)) / (n - 1),
      20 + rnd() * (h - 40),
    );
  });
}

Path routePathFromPoints(List<Offset> pts) {
  final path = Path();
  if (pts.isEmpty) return path;
  path.moveTo(pts.first.dx, pts.first.dy);
  for (var i = 1; i < pts.length; i++) {
    final prev = pts[i - 1];
    final cur = pts[i];
    final cx = (prev.dx + cur.dx) / 2;
    path.cubicTo(cx, prev.dy, cx, cur.dy, cur.dx, cur.dy);
  }
  return path;
}

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
