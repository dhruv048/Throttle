import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme.dart';

/// Who can see a ride, in a sentence.
String visibilityAudience(RideVisibility v) {
  switch (v) {
    case RideVisibility.public:
      return 'Anyone on Throttle can see it.';
    case RideVisibility.followers:
      return 'Only riders who follow you can see it.';
    case RideVisibility.private:
      return 'Only you can see it.';
  }
}

IconData visibilityIcon(RideVisibility v) => VisibilityPicker._icons[v]!;

/// Public / Followers / Private as one segmented control.
class VisibilityPicker extends StatelessWidget {
  const VisibilityPicker(
      {super.key, required this.value, required this.onChanged});

  final RideVisibility value;
  final ValueChanged<RideVisibility> onChanged;

  static const _icons = {
    RideVisibility.public: Icons.public,
    RideVisibility.followers: Icons.group_outlined,
    RideVisibility.private: Icons.lock_outline,
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          for (final v in RideVisibility.values)
            Expanded(child: _segment(v, on: v == value)),
        ],
      ),
    );
  }

  Widget _segment(RideVisibility v, {required bool on}) {
    final color = on ? AppColors.foreground : AppColors.mutedForeground;
    return Semantics(
      button: true,
      selected: on,
      child: GestureDetector(
        onTap: () => onChanged(v),
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          height: 40,
          decoration: BoxDecoration(
            color: on ? AppColors.card : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            boxShadow: on
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 6,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(_icons[v],
                  size: 16,
                  color: on ? AppColors.primary : AppColors.mutedForeground),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  v.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600, color: color),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Asks who should see a ride, starting from [current]. Null if dismissed.
Future<RideVisibility?> showVisibilitySheet(
    BuildContext context, RideVisibility current) {
  return showModalBottomSheet<RideVisibility>(
    context: context,
    backgroundColor: AppColors.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 20, 8, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child:
                  Text('Who can see this ride', style: displayStyle(size: 22)),
            ),
            for (final v in RideVisibility.values)
              ListTile(
                leading: Icon(visibilityIcon(v),
                    color: v == current
                        ? AppColors.primary
                        : AppColors.mutedForeground),
                title: Text(v.label,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(visibilityAudience(v)),
                trailing: v == current
                    ? const Icon(Icons.check, color: AppColors.primary)
                    : null,
                onTap: () => Navigator.pop(ctx, v),
              ),
          ],
        ),
      ),
    ),
  );
}
