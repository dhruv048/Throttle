import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../models/models.dart';
import '../theme.dart';
import '../widgets/photo_picker.dart';
import '../widgets/share_card.dart';

/// Builds a 1080×1350 (4:5) ride image and hands it to the OS share sheet.
class ShareRideScreen extends StatefulWidget {
  const ShareRideScreen({super.key, required this.item, this.design});

  final FeedItem item;

  /// The card's design, when it's also used elsewhere (the card posted with
  /// a ride): changes made here show up there too.
  final ValueNotifier<ShareCardDesign>? design;

  @override
  State<ShareRideScreen> createState() => _ShareRideScreenState();
}

class _ShareRideScreenState extends State<ShareRideScreen> {
  /// One per card, to capture whichever is tapped.
  final _cardKeys = {for (final s in ShareCardStyle.values) s: GlobalKey()};
  late final ValueNotifier<ShareCardDesign> _design =
      widget.design ?? ValueNotifier(ShareCardDesign.initial(item));

  /// The card being shared.
  ShareCardStyle? _sharing;

  FeedItem get item => widget.item;
  bool get _hasTrack => item.points.length >= 2;
  bool get _hasBikePhoto => item.bikePhotoUrl != null;

  @override
  void dispose() {
    if (widget.design == null) _design.dispose();
    super.dispose();
  }

  Future<void> _choosePhoto() async {
    final photo = await pickPhoto(context, title: 'Your photo');
    if (photo != null) {
      _design.value = _design.value.withPhoto(Uint8List.fromList(photo.bytes));
    }
  }

  /// Shares the card in [style] (and makes it the one posted with the ride).
  Future<void> _share(ShareCardStyle style) async {
    if (_sharing != null) return;
    final design = _design.value.withStyle(style);
    _design.value = design;
    setState(() => _sharing = style);
    try {
      final key = _cardKeys[style]!;
      final image =
          await renderShareCard(context, key, item: item, design: design);
      final png = await encodePng(image);
      image.dispose();

      final box = key.currentContext?.findRenderObject() as RenderBox?;
      final origin =
          box == null ? null : box.localToGlobal(Offset.zero) & box.size;
      final r = item.ride;
      final bike =
          item.bikeName?.isNotEmpty == true ? ' on my ${item.bikeName}' : '';
      await SharePlus.instance.share(ShareParams(
        files: [XFile.fromData(png, mimeType: 'image/png')],
        fileNameOverrides: [
          'throttle-ride-${DateTime.now().millisecondsSinceEpoch}.png'
        ],
        text:
            '${r.distanceKm.toStringAsFixed(1)} km ride$bike — recorded with Throttle',
        sharePositionOrigin: origin, // required on iPad
      ));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Couldn\'t share: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _sharing = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Text('Share ride', style: displayStyle(size: 20)),
      ),
      body: SafeArea(
        child: ValueListenableBuilder<ShareCardDesign>(
          valueListenable: _design,
          builder: (context, design, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                child: Row(
                  children: [
                    _rowLabel('Background'),
                    if (_hasBikePhoto)
                      _chip(design, 'Bike photo', ShareBackground.bike),
                    _chip(
                      design,
                      design.photo == null ? 'Your photo…' : 'Your photo',
                      ShareBackground.photo,
                      onTap: design.photo == null ? _choosePhoto : null,
                    ),
                    if (design.photo != null)
                      IconButton(
                        tooltip: 'Change photo',
                        onPressed: _choosePhoto,
                        icon: const Icon(Icons.edit_outlined, size: 18),
                      ),
                    if (_hasTrack)
                      _chip(design, 'Route map', ShareBackground.map),
                    _chip(design, 'Plain', ShareBackground.plain),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                child: Text('Tap a card to share it.',
                    style: monoStyle(size: 11, tracking: 0)),
              ),
              Expanded(
                // Not a lazy grid: every card stays built, to be captured.
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      const gap = 12.0;
                      final width = (constraints.maxWidth - gap) / 2;
                      return Wrap(
                        spacing: gap,
                        runSpacing: 16,
                        children: [
                          for (final style in ShareCardStyle.values)
                            SizedBox(
                              width: width,
                              child: _tile(design, style),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// One style of card: tap to share it.
  Widget _tile(ShareCardDesign design, ShareCardStyle style) {
    final sharing = _sharing == style;
    final current = widget.design != null && design.style == style;
    return Semantics(
      button: true,
      label: 'Share the ${style.label} card',
      child: GestureDetector(
        onTap: () => _share(style),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: ShareCard.size.aspectRatio,
              child: Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: current ? AppColors.primary : Colors.transparent,
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.10),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ShareCardFrame(
                      boundaryKey: _cardKeys[style]!,
                      item: item,
                      design: design.withStyle(style),
                    ),
                    if (sharing)
                      const ColoredBox(
                        color: Colors.black45,
                        child: Center(
                          child: CircularProgressIndicator(color: Colors.white),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(style.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600)),
                ),
                Icon(current ? Icons.check_circle : Icons.ios_share,
                    size: 16,
                    color: current
                        ? AppColors.primary
                        : AppColors.mutedForeground),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _rowLabel(String text) => Padding(
        padding: const EdgeInsets.only(right: 10),
        child: Text(text.toUpperCase(), style: labelMono(size: 9)),
      );

  Widget _chip(ShareCardDesign design, String label, ShareBackground value,
      {VoidCallback? onTap}) {
    final on = design.background == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: on,
        onSelected: (_) {
          if (onTap != null) {
            onTap();
          } else {
            _design.value = design.withBackground(value);
          }
        },
        selectedColor: AppColors.accent,
        labelStyle: TextStyle(
          fontWeight: FontWeight.w600,
          color: on ? AppColors.accentForeground : AppColors.mutedForeground,
        ),
        side: BorderSide(
            color: on
                ? AppColors.primary.withValues(alpha: 0.4)
                : AppColors.border),
        showCheckmark: false,
      ),
    );
  }
}
