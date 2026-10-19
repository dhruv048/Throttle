import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/recorder.dart';
import '../providers/rider.dart';
import '../theme.dart';
import '../widgets/bike_chooser.dart';
import '../widgets/bike_form_sheet.dart';
import '../widgets/live_ride_map.dart';
import '../widgets/ui.dart';
import 'post_ride_view.dart';
import '../units.dart';

/// Pick a bike and START; the live map and stats while riding; then the
/// finished ride, to save, share or delete ([PostRideView]). The ride itself is recorded by
/// [rideRecorderProvider] and [finishedRideProvider].
class RecordScreen extends ConsumerStatefulWidget {
  const RecordScreen({super.key});

  @override
  ConsumerState<RecordScreen> createState() => _RecordScreenState();
}

class _RecordScreenState extends ConsumerState<RecordScreen> {
  RideRecorder get _recorder => ref.read(rideRecorderProvider.notifier);

  @override
  void initState() {
    super.initState();
    ref.listenManual(backgroundLocationPromptProvider, (_, ask) {
      if (ask) _askForBackgroundLocation();
    });
  }

  /// Location only "while using the app" can stop a ride recording once the
  /// screen is off: explain, and offer the system setting.
  Future<void> _askForBackgroundLocation() async {
    final ios = defaultTargetPlatform == TargetPlatform.iOS;
    final allow = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.location_on_outlined, color: AppColors.primary),
        title: const Text('Keep recording with the screen off'),
        content: Text(
          ios
              ? 'Throttle needs location set to "Always" to keep recording '
                  'your ride when your phone is locked or you switch apps.\n\n'
                  'With "While Using the App", recording can stop when the '
                  'screen turns off.\n\n'
                  'In Settings, tap Location and choose Always.'
              : 'Throttle needs location set to "Allow all the time" to keep '
                  'recording your ride when your phone is locked or you '
                  'switch apps.\n\n'
                  'With "Allow only while using the app", recording can stop '
                  'when the screen turns off.',
          style: const TextStyle(height: 1.4),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Not now')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            child: Text(ios ? 'Open Settings' : 'Allow all the time'),
          ),
        ],
      ),
    );
    ref.read(backgroundLocationPromptProvider.notifier).dismiss();
    if (allow == true) await allowBackgroundLocation();
  }

  @override
  Widget build(BuildContext context) {
    final recording = ref.watch(rideRecorderProvider);
    final finished = ref.watch(finishedRideProvider);
    // Each finished ride gets a fresh form (and ride card).
    if (finished != null) {
      return PostRideView(key: ValueKey(finished.ride.localId));
    }
    if (recording.status == RideStatus.idle) return _buildChooser(recording);
    return _buildLive(recording);
  }

  /// Before the ride: pick the motorcycle, then START. Who can see the ride
  /// is decided after it.
  Widget _buildChooser(Recording recording) {
    final bikesState = ref.watch(myBikesProvider);
    final bikes = bikesState.value;
    final loadingBikes = bikesState.isLoading && bikes == null;
    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 24, 0, 24),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('RECORD', style: labelMono(size: 11)),
              Row(
                children: [
                  const BlinkDot(),
                  const SizedBox(width: 8),
                  Text(recording.gps, style: monoStyle(size: 11, tracking: 0)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text('Choose your ride', style: displayStyle(size: 32)),
        ),
        const SizedBox(height: 14),
        RiseIn(
          child: BikeChooser(
            loading: loadingBikes,
            bikes: bikes ?? const [],
            selectedId: ref.watch(selectedBikeProvider)?.id,
            onSelect: (b) => ref.read(pickedBikeIdProvider.notifier).pick(b.id),
            // Saving a bike reloads the bikes, and with them this list.
            onAdd: () => showBikeFormSheet(context,
                defaultPrimary: bikes?.isEmpty ?? true),
          ),
        ),
        if (!loadingBikes && (bikes?.isEmpty ?? true))
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
            child: Text(
              bikes == null
                  ? 'Couldn\'t load your bikes — this ride will count toward your primary bike.'
                  : 'Add your bike to see its km grow with every ride.',
              style: const TextStyle(
                  fontSize: 13, color: AppColors.mutedForeground),
            ),
          ),
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: SheenButton(
            onTap: () => _recorder.ride(),
            child: Container(
              height: 64,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text('START',
                  style: displayStyle(
                      size: 24, color: AppColors.primaryForeground)),
            ),
          ),
        ),
      ],
    );
  }

  /// During the ride: live map with the stats and controls overlaid.
  Widget _buildLive(Recording recording) {
    final riding = recording.status == RideStatus.riding;
    return Stack(
      children: [
        Positioned.fill(
          child: LiveRideMap(
            trail: recording.trail,
            here: recording.here,
            accuracyM: recording.hereAccuracy,
            recording: riding,
            // Clear of the stats card (taller with the "restored" note).
            topInset: recording.restored ? 250 : 196,
            bottomInset: 92,
          ),
        ),
        Positioned(
          top: 12,
          left: 12,
          right: 12,
          child: _Overlay(
            child: Column(
              children: [
                Row(
                  children: [
                    if (riding)
                      const BlinkDot()
                    else
                      const Icon(Icons.pause, size: 12),
                    const SizedBox(width: 6),
                    Text(
                      riding ? 'RECORDING' : 'PAUSED',
                      style: labelMono(
                          size: 11, color: riding ? AppColors.primary : null),
                    ),
                    const Spacer(),
                    Text(recording.gps,
                        style: monoStyle(size: 10, tracking: 0)),
                  ],
                ),
                if (recording.restored)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(top: 8, bottom: 4),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.accent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.restore,
                            size: 16, color: AppColors.accentForeground),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Throttle was closed during this ride. Everything '
                            'up to then is kept: RESUME to carry on, or FINISH.',
                            style: TextStyle(
                                fontSize: 12,
                                height: 1.3,
                                color: AppColors.accentForeground),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 2),
                Text.rich(
                  TextSpan(children: [
                    TextSpan(
                        text:
                            '${context.units.speed(recording.speedKmh).round()}',
                        style: displayStyle(size: 64)),
                    TextSpan(
                      text: ' ${context.units.speedUnit}',
                      style: displayStyle(
                          size: 16, color: AppColors.mutedForeground),
                    ),
                  ]),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                        child: _LiveStat(
                            value: context.units.fixed(recording.km, 2),
                            unit: context.units.distanceUnit,
                            label: 'Distance')),
                    Expanded(
                        child: _LiveStat(
                            value: clock(recording.secs), label: 'Time')),
                    Expanded(
                        child: _LiveStat(
                            value:
                                '${context.units.speed(recording.avgKmh).round()}',
                            unit: context.units.speedUnit,
                            label: 'Avg speed')),
                  ],
                ),
              ],
            ),
          ),
        ),
        Positioned(
          left: 12,
          right: 12,
          bottom: 12,
          child: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 64,
                  child: FilledButton(
                    onPressed: () =>
                        riding ? _recorder.pause() : _recorder.ride(),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: AppColors.foreground,
                      elevation: 3,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                    child: Text(riding ? 'PAUSE' : 'RESUME',
                        style: displayStyle(size: 20)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 64,
                  child: FilledButton(
                    onPressed: () => _recorder.finish(),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.foreground,
                      foregroundColor: AppColors.background,
                      elevation: 3,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                    child: Text('FINISH',
                        style: displayStyle(
                            size: 20, color: AppColors.background)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Translucent card that floats over the live map.
class _Overlay extends StatelessWidget {
  const _Overlay({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.93),
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
              color: Color(0x26000000), blurRadius: 16, offset: Offset(0, 4)),
        ],
      ),
      child: child,
    );
  }
}

class _LiveStat extends StatelessWidget {
  const _LiveStat({required this.value, required this.label, this.unit = ''});

  final String value;
  final String unit;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(children: [
            TextSpan(text: value, style: displayStyle(size: 22)),
            if (unit.isNotEmpty)
              TextSpan(
                text: ' $unit',
                style: displayStyle(size: 12, color: AppColors.mutedForeground),
              ),
          ]),
          maxLines: 1,
        ),
        LabelMono(label),
      ],
    );
  }
}
