import 'package:flutter/material.dart';
import '../data.dart';
import '../theme.dart';
import '../widgets/ui.dart';

class ActivityScreen extends StatelessWidget {
  const ActivityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final max = weeklyKm.reduce((a, b) => a > b ? a : b);
    return ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        const PageHeader(eyebrow: 'This year', title: 'Activity'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.55,
            children: [
              _stat(formatNumber(me.km), 'km ridden'),
              _stat('${me.rides}', 'rides'),
              _stat(formatNumber(me.elev), 'm climbed'),
              _stat('${me.hours}', 'hours'),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: AppCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const LabelMono('Weekly km'),
                    Text('Last 8 weeks', style: monoStyle(size: 11, tracking: 0, color: AppColors.primary)),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 128,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (var i = 0; i < weeklyKm.length; i++) ...[
                        if (i > 0) const SizedBox(width: 8),
                        Expanded(
                          child: Container(
                            height: (weeklyKm[i] / max) * 128,
                            decoration: BoxDecoration(
                              color: i == weeklyKm.length - 1 ? AppColors.primary : AppColors.secondary,
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: AppCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const LabelMono('Challenge'),
                const SizedBox(height: 4),
                Text('September 500 km', style: displayStyle(size: 20)),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: const LinearProgressIndicator(
                    value: 0.72,
                    minHeight: 8,
                    backgroundColor: AppColors.secondary,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 8),
                Text('362 / 500 km', style: monoStyle(size: 11, tracking: 0)),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const LabelMono('Recent rides'),
              const SizedBox(height: 8),
              AppCard(
                child: Column(
                  children: [
                    for (var i = 0; i < 2; i++) ...[
                      if (i > 0) const Divider(height: 1, color: AppColors.border),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(rides[i].title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                                  Text('${rides[i].ago} · ${rides[i].duration}', style: monoStyle(size: 11, tracking: 0)),
                                ],
                              ),
                            ),
                            Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(text: '${rides[i].km}', style: displayStyle(size: 20)),
                                  TextSpan(text: ' km', style: displayStyle(size: 12, color: AppColors.mutedForeground)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _stat(String v, String l) {
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(v, style: displayStyle(size: 30)),
          const SizedBox(height: 8),
          LabelMono(l),
        ],
      ),
    );
  }
}
