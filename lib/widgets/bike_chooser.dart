import 'package:flutter/material.dart';

import '../data.dart';
import '../models/models.dart';
import '../theme.dart';
import 'ui.dart';

/// Horizontal row of the rider's bikes (with photos) to pick one for a ride.
class BikeChooser extends StatelessWidget {
  const BikeChooser({
    super.key,
    required this.bikes,
    required this.selectedId,
    required this.onSelect,
    required this.onAdd,
  });

  final List<BikeRecord> bikes;
  final String? selectedId;
  final ValueChanged<BikeRecord> onSelect;
  final VoidCallback onAdd;

  static const _cardWidth = 200.0;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 196,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: bikes.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          if (i == bikes.length) return _addCard();
          final bike = bikes[i];
          return _bikeCard(bike, selected: bike.id == selectedId);
        },
      ),
    );
  }

  Widget _bikeCard(BikeRecord bike, {required bool selected}) {
    return GestureDetector(
      onTap: () => onSelect(bike),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: _cardWidth,
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
            Stack(
              children: [
                SizedBox(
                  height: 112,
                  width: double.infinity,
                  child: bike.photoUrl != null
                      ? Image.network(
                          bike.photoUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _photoPlaceholder(),
                        )
                      : _photoPlaceholder(),
                ),
                if (selected)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.check,
                          size: 16, color: Colors.white),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              child: Text(
                bike.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: displayStyle(size: 18),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 2, 12, 0),
              child: Text(
                [
                  '${formatDistance(bike.riddenKm)} km',
                  if (bike.isPrimary) 'Primary',
                ].join(' · '),
                style: monoStyle(size: 11, tracking: 0),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _photoPlaceholder() => const ColoredBox(
        color: AppColors.panel,
        child: Center(
          child: Icon(Icons.two_wheeler,
              size: 44, color: AppColors.mutedForeground),
        ),
      );

  Widget _addCard() {
    return GestureDetector(
      onTap: onAdd,
      child: Container(
        width: 120,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.border),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add, color: AppColors.mutedForeground),
            SizedBox(height: 6),
            LabelMono('Add bike'),
          ],
        ),
      ),
    );
  }
}
