import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// Plays a bundled video on loop (muted unless [muted] is false), covering its
/// box. Shows [fallback] while loading or when the asset is missing — e.g. in
/// a clean checkout without the local comparison placeholders.
class LoopingVideo extends StatefulWidget {
  final String asset;
  final bool muted;
  final Widget fallback;
  const LoopingVideo({super.key, required this.asset, this.muted = true, required this.fallback});
  @override
  State<LoopingVideo> createState() => _LoopingVideoState();
}

class _LoopingVideoState extends State<LoopingVideo> {
  VideoPlayerController? _c;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    final c = VideoPlayerController.asset(widget.asset);
    _c = c;
    c.initialize().then((_) {
      if (!mounted) return;
      c
        ..setLooping(true)
        ..setVolume(widget.muted ? 0 : 1)
        ..play();
      setState(() => _ready = true);
    }).catchError((_) {
      // asset not extracted locally: keep the fallback
    });
  }

  @override
  void didUpdateWidget(LoopingVideo old) {
    super.didUpdateWidget(old);
    if (old.muted != widget.muted) _c?.setVolume(widget.muted ? 0 : 1);
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    if (!_ready || c == null) return widget.fallback;
    return FittedBox(
      fit: BoxFit.cover,
      clipBehavior: Clip.hardEdge,
      child: SizedBox(width: c.value.size.width, height: c.value.size.height, child: VideoPlayer(c)),
    );
  }
}
