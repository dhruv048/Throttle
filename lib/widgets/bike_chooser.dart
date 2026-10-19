import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme.dart';
import 'skeleton.dart';
import 'ui.dart';
import '../units.dart';

/// The rider's bikes (with photos), two to a row, to pick one for a ride.
class BikeChooser extends StatelessWidget {
  const BikeChooser({
    super.key,
    required this.bikes,
    required this.selectedId,
    required this.onSelect,
    required this.onAdd,
    this.loading = false,
  });

  /// Shows placeholder cards instead of [bikes] while they load.
  final bool loading;
  final List<BikeRecord> bikes;
  final String? selectedId;
  final ValueChanged<BikeRecord> onSelect;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return BikeGrid(
      loading: loading,
      bikes: bikes,
      tile: (bike) => BikeTile(
        bike: bike,
        selected: bike.id == selectedId,
        onTap: () => onSelect(bike),
      ),
      onAdd: onAdd,
    );
  }
}

/// Bikes laid out two to a row, the cells in each row the same height,
/// optionally ending with an "Add bike" cell.
class BikeGrid extends StatelessWidget {
  const BikeGrid({
    super.key,
    required this.bikes,
    required this.tile,
    this.onAdd,
    this.addLabel = 'Add bike',
    this.loading = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 20),
  });

  final List<BikeRecord> bikes;
  final Widget Function(BikeRecord bike) tile;
  final VoidCallback? onAdd;
  final String addLabel;

  /// Shows two placeholder cells instead of [bikes].
  final bool loading;
  final EdgeInsetsGeometry padding;

  static const _gap = 12.0;

  @override
  Widget build(BuildContext context) {
    final cells = loading
        ? const [BikeTile.skeleton(), BikeTile.skeleton()]
        : [
            for (final bike in bikes) tile(bike),
            if (onAdd != null) _AddBikeTile(label: addLabel, onTap: onAdd!),
          ];
    return Padding(
      padding: padding,
      child: Column(
        children: [
          for (var i = 0; i < cells.length; i += 2)
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : _gap),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: cells[i]),
                    const SizedBox(width: _gap),
                    Expanded(
                      child: i + 1 < cells.length
                          ? cells[i + 1]
                          : const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// One bike: its photo (or a placeholder), name and km ridden.
class BikeTile extends StatelessWidget {
  const BikeTile({
    super.key,
    required BikeRecord this.bike,
    this.selected = false,
    this.onTap,
    this.subtitle,
    this.badge,
    this.editable = false,
  });

  const BikeTile.skeleton({super.key})
      : bike = null,
        selected = false,
        onTap = null,
        subtitle = null,
        badge = null,
        editable = false;

  /// Null for a loading placeholder.
  final BikeRecord? bike;

  /// Picked for the next ride: an orange outline and a check mark.
  final bool selected;
  final VoidCallback? onTap;

  /// The line under the name; km ridden (and "Primary") by default.
  final String? subtitle;

  /// A label on the photo's corner, e.g. "Primary".
  final String? badge;

  /// Shows a pencil: tapping edits the bike.
  final bool editable;

  @override
  Widget build(BuildContext context) {
    final bike = this.bike;
    if (bike == null) return _skeleton();
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
            width: selected ? 2.5 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: selected ? 0.10 : 0.04),
              blurRadius: selected ? 14 : 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 4 / 3,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  bike.photoUrl != null
                      ? NetworkPhoto(bike.photoUrl!, fallback: _placeholder())
                      : _placeholder(),
                  if (badge != null)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(badge!.toUpperCase(),
                            style: labelMono(
                                size: 9, color: AppColors.primaryForeground)),
                      ),
                    ),
                  if (selected)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: _badge(Icons.check, AppColors.primary,
                          iconColor: Colors.white),
                    )
                  else if (editable)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: _badge(Icons.edit_outlined,
                          Colors.white.withValues(alpha: 0.9)),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    bike.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: displayStyle(size: 17),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle ??
                        [
                          context.units.totalText(bike.riddenKm),
                          if (bike.isPrimary) 'Primary',
                        ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: monoStyle(size: 11, tracking: 0),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _badge(IconData icon, Color color,
          {Color iconColor = AppColors.foreground}) =>
      Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        child: Icon(icon, size: 14, color: iconColor),
      );

  static Widget _placeholder() => const ColoredBox(
        color: AppColors.panel,
        child: Center(
          child: Icon(Icons.two_wheeler,
              size: 40, color: AppColors.mutedForeground),
        ),
      );

  Widget _skeleton() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: const Shimmer(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(aspectRatio: 4 / 3, child: SkeletonBox(radius: 0)),
            Padding(
              padding: EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: SkeletonBox(width: 110, height: 15),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(12, 8, 12, 14),
              child: SkeletonBox(width: 70, height: 10),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddBikeTile extends StatelessWidget {
  const _AddBikeTile({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: CustomPaint(
          painter: const DashedRRectPainter(radius: 18),
          // Keeps its size when it starts a row by itself.
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 120),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.add, color: AppColors.mutedForeground),
                const SizedBox(height: 6),
                LabelMono(label),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
