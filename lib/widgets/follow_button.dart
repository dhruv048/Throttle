import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/rider.dart';
import '../theme.dart';
import 'skeleton.dart';

/// Follow / Following for one rider. Changes show right away and are put
/// back if they don't go through.
class FollowButton extends ConsumerStatefulWidget {
  const FollowButton({
    super.key,
    required this.riderId,
    this.width = 82,
    this.height = 32,
    this.followLabel = 'Follow',
  });

  final String riderId;
  final double width;
  final double height;

  /// e.g. "Follow back".
  final String followLabel;

  @override
  ConsumerState<FollowButton> createState() => _FollowButtonState();
}

class _FollowButtonState extends ConsumerState<FollowButton> {
  bool _busy = false;

  Future<void> _toggle() async {
    if (_busy || !ref.read(followingProvider).hasValue) return;
    setState(() => _busy = true);
    try {
      await ref.read(followingProvider.notifier).toggle(widget.riderId);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Couldn\'t update — check your connection.')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final following = ref.watch(
        followingProvider.select((ids) => ids.value?.contains(widget.riderId)));
    if (following == null) {
      return Shimmer(
        child:
            SkeletonBox(width: widget.width, height: widget.height, radius: 8),
      );
    }
    return Semantics(
      button: true,
      child: GestureDetector(
        onTap: _busy ? null : _toggle,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: widget.width,
          height: widget.height,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: following ? AppColors.secondary : AppColors.primary,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: following ? AppColors.border : AppColors.primary),
          ),
          child: Text(
            following ? 'Following' : widget.followLabel,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: following
                  ? AppColors.foreground
                  : AppColors.primaryForeground,
            ),
          ),
        ),
      ),
    );
  }
}
