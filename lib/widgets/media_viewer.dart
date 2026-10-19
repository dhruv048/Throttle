import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../models/models.dart';
import '../theme.dart';
import 'skeleton.dart';

/// A journal photo (cropped to fill) or video (a play tile; videos aren't
/// downloaded until they're opened).
class MediaThumb extends StatelessWidget {
  const MediaThumb(this.media, {super.key, this.iconSize = 28});

  final RideMedia media;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    if (!media.isVideo) return NetworkPhoto(media.url);
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2B2D33), Color(0xFF14151A)],
        ),
      ),
      child: Center(
        child: Container(
          padding: EdgeInsets.all(iconSize * 0.25),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.play_arrow_rounded,
              size: iconSize, color: Colors.white),
        ),
      ),
    );
  }
}

/// Opens [media] full screen at [index]; swipe for the others.
Future<void> openMediaViewer(
    BuildContext context, List<RideMedia> media, int index) {
  return Navigator.of(context).push(PageRouteBuilder<void>(
    opaque: false,
    barrierColor: Colors.black,
    pageBuilder: (_, __, ___) => MediaViewer(media: media, initialIndex: index),
    transitionsBuilder: (_, animation, __, child) =>
        FadeTransition(opacity: animation, child: child),
  ));
}

class MediaViewer extends StatefulWidget {
  const MediaViewer(
      {super.key, required this.media, required this.initialIndex});

  final List<RideMedia> media;
  final int initialIndex;

  @override
  State<MediaViewer> createState() => _MediaViewerState();
}

class _MediaViewerState extends State<MediaViewer> {
  late final _pages = PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final current = widget.media[_index];
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _pages,
            itemCount: widget.media.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (_, i) {
              final m = widget.media[i];
              return m.isVideo
                  ? _VideoPage(url: m.url)
                  : InteractiveViewer(
                      maxScale: 4,
                      child: Center(
                        child: NetworkPhoto(m.url, fit: BoxFit.contain),
                      ),
                    );
            },
          ),
          SafeArea(
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close, color: Colors.white),
                ),
                // Which ride it's from, among a rider's memories.
                Expanded(
                  child: Text(current.rideTitle ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600)),
                ),
                if (widget.media.length > 1)
                  Padding(
                    padding: const EdgeInsets.only(right: 16),
                    child: Text('${_index + 1} / ${widget.media.length}',
                        style: monoStyle(size: 12, color: Colors.white)),
                  ),
              ],
            ),
          ),
          if (current.caption?.isNotEmpty == true)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: IgnorePointer(
                child: Container(
                  padding: const EdgeInsets.fromLTRB(20, 32, 20, 20),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black87],
                    ),
                  ),
                  child: SafeArea(
                    top: false,
                    child: Text(current.caption!,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 15, height: 1.4)),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Plays a video while it's on screen; tap to pause.
class _VideoPage extends StatefulWidget {
  const _VideoPage({required this.url});

  final String url;

  @override
  State<_VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends State<_VideoPage> {
  late final VideoPlayerController _video =
      VideoPlayerController.networkUrl(Uri.parse(widget.url));
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _video.setLooping(true);
    _video.initialize().then((_) {
      if (mounted) {
        setState(() {});
        _video.play();
      }
    }, onError: (Object _) {
      if (mounted) setState(() => _failed = true);
    });
  }

  @override
  void dispose() {
    _video.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return Center(
        child: Text('Couldn\'t play this video.',
            style: monoStyle(size: 12, color: Colors.white70)),
      );
    }
    if (!_video.value.isInitialized) {
      return const Center(
          child: CircularProgressIndicator(color: Colors.white));
    }
    return GestureDetector(
      onTap: () => setState(
          () => _video.value.isPlaying ? _video.pause() : _video.play()),
      child: Stack(
        alignment: Alignment.center,
        children: [
          AspectRatio(
            aspectRatio: _video.value.aspectRatio,
            child: VideoPlayer(_video),
          ),
          ValueListenableBuilder<VideoPlayerValue>(
            valueListenable: _video,
            builder: (_, value, __) => AnimatedOpacity(
              opacity: value.isPlaying ? 0 : 1,
              duration: const Duration(milliseconds: 150),
              child: const Icon(Icons.play_circle_fill,
                  size: 64, color: Colors.white70),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: SafeArea(
              top: false,
              child: VideoProgressIndicator(
                _video,
                allowScrubbing: true,
                colors: VideoProgressColors(
                  playedColor: AppColors.primary,
                  bufferedColor: Colors.white.withValues(alpha: 0.3),
                  backgroundColor: Colors.white.withValues(alpha: 0.15),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
