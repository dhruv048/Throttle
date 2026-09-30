import 'package:flutter/material.dart';
import '../theme.dart';

class RiderAvatar extends StatelessWidget {
  const RiderAvatar({super.key, required this.initials, this.size = 36});

  final String initials;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.secondary,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        initials,
        style: monoStyle(size: 11, weight: FontWeight.w500, tracking: 0),
      ),
    );
  }
}
