import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MediaPlayerScreen extends StatefulWidget {
  final String url;
  final String title;

  const MediaPlayerScreen({super.key, required this.url, required this.title});

  @override
  State<MediaPlayerScreen> createState() => _MediaPlayerScreenState();
}

class _MediaPlayerScreenState extends State<MediaPlayerScreen> {
  late final Player player;
  late final VideoController controller;
  bool _initialized = false;
  Duration _savedPosition = Duration.zero;

  @override
  void initState() {
    super.initState();
    player = Player();
    controller = VideoController(player);
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    final prefs = await SharedPreferences.getInstance();
    final posMillis = prefs.getInt('playback_pos_${widget.url}') ?? 0;
    _savedPosition = Duration(milliseconds: posMillis);

    player.stream.playing.listen((playing) {
      if (playing && !_initialized && _savedPosition.inMilliseconds > 0) {
        _initialized = true;
        player.seek(_savedPosition);
      }
    });

    await player.open(Media(widget.url));
  }

  @override
  void dispose() {
    final int pos = player.state.position.inMilliseconds;
    if (pos > 0) {
      SharedPreferences.getInstance().then((prefs) {
        prefs.setInt('playback_pos_${widget.url}', pos);
      });
    }

    player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: MaterialVideoControlsTheme(
        normal: MaterialVideoControlsThemeData(
          buttonBarHeight: 64.0,
          buttonBarButtonSize: 28.0,
          primaryButtonBar: [
            const Spacer(),
            const MaterialSkipPreviousButton(iconSize: 48),
            const MaterialPlayOrPauseButton(iconSize: 64),
            const MaterialSkipNextButton(iconSize: 48),
            const Spacer(),
          ],
          bottomButtonBar: const [
            MaterialPositionIndicator(),
            Spacer(),
            MaterialDesktopVolumeButton(), // Fallback for volume
            MaterialFullscreenButton(),
          ],
          topButtonBar: [
            IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back, color: Colors.white),
            ),
            Expanded(
              child: Text(
                widget.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        fullscreen: const MaterialVideoControlsThemeData(
          primaryButtonBar: [
            Spacer(),
            MaterialSkipPreviousButton(iconSize: 56),
            MaterialPlayOrPauseButton(iconSize: 80),
            MaterialSkipNextButton(iconSize: 56),
            Spacer(),
          ],
          bottomButtonBar: [
            MaterialPositionIndicator(),
            Spacer(),
            MaterialDesktopVolumeButton(),
            MaterialFullscreenButton(),
          ],
        ),
        child: Video(
          controller: controller,
          controls: MaterialVideoControls,
        ),
      ),
    );
  }
}
