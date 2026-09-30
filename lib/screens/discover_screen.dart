import 'package:flutter/material.dart';
import '../data.dart';
import '../theme.dart';
import '../widgets/rider_avatar.dart';
import '../widgets/route_map.dart';
import '../widgets/ui.dart';

class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key});

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  String tab = 'Routes';
  String q = '';

  bool match(String s) => s.toLowerCase().contains(q.toLowerCase());

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        const PageHeader(eyebrow: 'Kathmandu valley', title: 'Discover'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.search, size: 16, color: AppColors.mutedForeground),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        onChanged: (v) => setState(() => q = v),
                        decoration: const InputDecoration(
                          hintText: 'Search roads, riders, clubs',
                          hintStyle: TextStyle(fontSize: 14, color: AppColors.mutedForeground),
                          border: InputBorder.none,
                          isDense: true,
                        ),
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: ['Routes', 'Riders', 'Clubs'].map((t) {
                  final on = tab == t;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: () => setState(() => tab = t),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        decoration: BoxDecoration(
                          color: on ? AppColors.foreground : AppColors.card,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: on ? AppColors.foreground : AppColors.border),
                        ),
                        child: Text(
                          t.toUpperCase(),
                          style: monoStyle(
                            size: 11,
                            tracking: 1.32,
                            color: on ? AppColors.background : AppColors.mutedForeground,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            clipBehavior: Clip.antiAlias,
            child: const RouteMap(seed: 21, height: 176, label: 'Heatmap · last 30 days'),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const LabelMono('Popular nearby'),
              const SizedBox(height: 8),
              if (tab == 'Routes')
                ...routes.where((r) => match(r.name)).map(
                      (r) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: AppCard(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: SizedBox(
                                  width: 96,
                                  child: RouteMap(seed: r.seed, height: 80),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(r.name, style: displayStyle(size: 18)),
                                    const SizedBox(height: 4),
                                    Text('${r.km} km · ${r.time}', style: monoStyle(size: 11, tracking: 0)),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${r.riders} riders · ${r.difficulty}',
                                      style: monoStyle(size: 11, tracking: 0, color: AppColors.primary),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
              if (tab == 'Riders')
                ...riders.where((r) => match(r.name)).map(
                      (r) => FollowRow(
                        initials: r.initials,
                        name: r.name,
                        sub: '${r.bike} · ${r.km}',
                        cta: 'Follow',
                      ),
                    ),
              if (tab == 'Clubs')
                ...clubs.where((c) => match(c.name)).map(
                      (c) => FollowRow(
                        initials: c.initials,
                        name: c.name,
                        sub: '${formatNumber(c.members)} members',
                        cta: 'Join',
                      ),
                    ),
            ],
          ),
        ),
      ],
    );
  }
}

class FollowRow extends StatefulWidget {
  const FollowRow({
    super.key,
    required this.initials,
    required this.name,
    required this.sub,
    required this.cta,
  });

  final String initials;
  final String name;
  final String sub;
  final String cta;

  @override
  State<FollowRow> createState() => _FollowRowState();
}

class _FollowRowState extends State<FollowRow> {
  bool on = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            RiderAvatar(initials: widget.initials, size: 44),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  Text(widget.sub, style: monoStyle(size: 11, tracking: 0)),
                ],
              ),
            ),
            GestureDetector(
              onTap: () => setState(() => on = !on),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: on ? AppColors.secondary : AppColors.primary,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  on ? '✓' : widget.cta,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: on ? AppColors.foreground : AppColors.primaryForeground,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
