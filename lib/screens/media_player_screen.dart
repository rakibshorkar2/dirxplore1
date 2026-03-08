import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'dart:async';

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

  double _brightness = 0.5;
  double _volume = 0.5;
  bool _showOverlay = false;
  String _overlayType =
      ''; // 'brightness', 'volume', 'seek', 'speed', 'lock', 'audio', 'subtitle', 'fit'
  Timer? _overlayTimer;

  bool _isLocked = false;
  double _playbackSpeed = 1.0;
  BoxFit _fitMode = BoxFit.contain;
  Duration _tempSeekPosition = Duration.zero;
  bool _isSeekingHorizontally = false;

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

    // Initialize brightness and volume
    try {
      _brightness = await ScreenBrightness().current;
    } catch (_) {
      _brightness = 0.5;
    }
    _volume = player.state.volume / 100.0;

    player.stream.playing.listen((playing) {
      if (playing && !_initialized && _savedPosition.inMilliseconds > 0) {
        _initialized = true;
        player.seek(_savedPosition);
      }
    });

    await player.open(Media(widget.url));
  }

  void _showControlOverlay(String type) {
    setState(() {
      _overlayType = type;
      _showOverlay = true;
    });
    _overlayTimer?.cancel();
    _overlayTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() => _showOverlay = false);
      }
    });
  }

  void _handleVerticalDrag(DragUpdateDetails details, double screenWidth) {
    if (_isLocked) return;
    final isLeft = details.globalPosition.dx < screenWidth / 2;
    final delta = -details.primaryDelta! / 200.0; // Sensitivity adjustment

    if (isLeft) {
      // Brightness
      setState(() {
        _brightness = (_brightness + delta).clamp(0.0, 1.0);
        ScreenBrightness().setScreenBrightness(_brightness);
        _showControlOverlay('brightness');
      });
    } else {
      // Volume
      setState(() {
        _volume = (_volume + delta).clamp(0.0, 1.0);
        player.setVolume(_volume * 100.0);
        _showControlOverlay('volume');
      });
    }
  }

  void _handleHorizontalDragUpdate(
      DragUpdateDetails details, double screenWidth) {
    if (_isLocked) return;
    if (!_isSeekingHorizontally) {
      _isSeekingHorizontally = true;
      _tempSeekPosition = player.state.position;
    }

    final delta = details.primaryDelta! / screenWidth;
    final seekDelta =
        Duration(seconds: (player.state.duration.inSeconds * delta).toInt());

    setState(() {
      _tempSeekPosition = _tempSeekPosition + seekDelta;
      if (_tempSeekPosition < Duration.zero) _tempSeekPosition = Duration.zero;
      if (_tempSeekPosition > player.state.duration) {
        _tempSeekPosition = player.state.duration;
      }
      _showControlOverlay('seek');
    });
  }

  void _handleHorizontalDragEnd(DragEndDetails details) {
    if (_isLocked) return;
    if (_isSeekingHorizontally) {
      player.seek(_tempSeekPosition);
      _isSeekingHorizontally = false;
    }
  }

  void _handleDoubleTap(TapDownDetails details, double screenWidth) {
    if (_isLocked) return;
    final isLeft = details.globalPosition.dx < screenWidth / 2;
    final seekAmount = isLeft ? -10 : 10;
    var newPosition = player.state.position + Duration(seconds: seekAmount);
    if (newPosition < Duration.zero) {
      newPosition = Duration.zero;
    }
    if (newPosition > player.state.duration) {
      newPosition = player.state.duration;
    }

    player.seek(newPosition);
    _showControlOverlay(isLeft ? 'seek_back' : 'seek_forward');
  }

  void _toggleLock() {
    setState(() {
      _isLocked = !_isLocked;
      _showControlOverlay('lock');
    });
  }

  void _cycleFitMode() {
    setState(() {
      if (_fitMode == BoxFit.contain) {
        _fitMode = BoxFit.cover;
      } else if (_fitMode == BoxFit.cover) {
        _fitMode = BoxFit.fill;
      } else {
        _fitMode = BoxFit.contain;
      }
      _showControlOverlay('fit');
    });
  }

  void _showSpeedBottomSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black87,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        final speeds = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: speeds.map((speed) {
              return ListTile(
                title: Text(
                  '${speed}x',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _playbackSpeed == speed ? Colors.blue : Colors.white,
                    fontWeight: _playbackSpeed == speed
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
                onTap: () {
                  setState(() {
                    _playbackSpeed = speed;
                    player.setRate(speed);
                    _showControlOverlay('speed');
                  });
                  Navigator.pop(context);
                },
              );
            }).toList(),
          ),
        );
      },
    );
  }

  void _showAudioTrackBottomSheet() {
    final tracks = player.state.tracks.audio;
    final current = player.state.track.audio;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black87,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Audio Tracks',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold)),
              const Divider(color: Colors.white24),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: tracks.length,
                  itemBuilder: (context, index) {
                    final track = tracks[index];
                    final isSelected = track == current;
                    return ListTile(
                      title: Text(
                        track.title ?? track.language ?? 'Track ${index + 1}',
                        style: TextStyle(
                          color: isSelected ? Colors.blue : Colors.white,
                        ),
                      ),
                      trailing: isSelected
                          ? const Icon(Icons.check, color: Colors.blue)
                          : null,
                      onTap: () {
                        player.setAudioTrack(track);
                        Navigator.pop(context);
                        _showControlOverlay('audio');
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showSubtitleTrackBottomSheet() {
    final tracks = player.state.tracks.subtitle;
    final current = player.state.track.subtitle;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black87,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Subtitles',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold)),
              const Divider(color: Colors.white24),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: tracks.length,
                  itemBuilder: (context, index) {
                    final track = tracks[index];
                    final isSelected = track == current;
                    return ListTile(
                      title: Text(
                        track.title ??
                            track.language ??
                            (index == 0 ? 'None' : 'Subtitle $index'),
                        style: TextStyle(
                          color: isSelected ? Colors.blue : Colors.white,
                        ),
                      ),
                      trailing: isSelected
                          ? const Icon(Icons.check, color: Colors.blue)
                          : null,
                      onTap: () {
                        player.setSubtitleTrack(track);
                        Navigator.pop(context);
                        _showControlOverlay('subtitle');
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    if (duration.inHours > 0) {
      return "${twoDigits(duration.inHours)}:$twoDigitMinutes:$twoDigitSeconds";
    }
    return "$twoDigitMinutes:$twoDigitSeconds";
  }

  @override
  void dispose() {
    _overlayTimer?.cancel();
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
            IconButton(
              onPressed: _cycleFitMode,
              icon: const Icon(Icons.aspect_ratio, color: Colors.white),
              tooltip: 'Aspect Ratio',
            ),
            TextButton(
              onPressed: _showSpeedBottomSheet,
              child: Text(
                '${_playbackSpeed}x',
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
            IconButton(
              onPressed: _showAudioTrackBottomSheet,
              icon: const Icon(Icons.audiotrack, color: Colors.white),
              tooltip: 'Audio Tracks',
            ),
            IconButton(
              onPressed: _showSubtitleTrackBottomSheet,
              icon: const Icon(Icons.subtitles, color: Colors.white),
              tooltip: 'Subtitles',
            ),
            IconButton(
              onPressed: _toggleLock,
              icon: Icon(_isLocked ? Icons.lock : Icons.lock_open,
                  color: Colors.white),
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
        child: Stack(
          children: [
            GestureDetector(
              onVerticalDragUpdate: (details) => _handleVerticalDrag(
                  details, MediaQuery.of(context).size.width),
              onHorizontalDragUpdate: (details) => _handleHorizontalDragUpdate(
                  details, MediaQuery.of(context).size.width),
              onHorizontalDragEnd: _handleHorizontalDragEnd,
              onDoubleTapDown: (details) =>
                  _handleDoubleTap(details, MediaQuery.of(context).size.width),
              child: Video(
                controller: controller,
                controls: _isLocked
                    ? (state) => const SizedBox.shrink()
                    : MaterialVideoControls,
                fit: _fitMode,
              ),
            ),
            if (_isLocked)
              Positioned(
                left: 20,
                top: MediaQuery.of(context).size.height / 2 - 25,
                child: IconButton(
                  color: Colors.white54,
                  iconSize: 50,
                  icon: const Icon(Icons.lock_outline),
                  onPressed: _toggleLock,
                ),
              ),
            if (_showOverlay)
              Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildOverlayIcon(),
                      const SizedBox(height: 8),
                      _buildOverlayContent(),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildOverlayIcon() {
    IconData icon;
    switch (_overlayType) {
      case 'brightness':
        icon = Icons.brightness_6;
        break;
      case 'volume':
        icon = Icons.volume_up;
        break;
      case 'seek_forward':
        icon = Icons.fast_forward;
        break;
      case 'seek_back':
        icon = Icons.fast_rewind;
        break;
      case 'seek':
        icon = Icons.compare_arrows;
        break;
      case 'speed':
        icon = Icons.speed;
        break;
      case 'lock':
        icon = _isLocked ? Icons.lock : Icons.lock_open;
        break;
      case 'fit':
        icon = Icons.aspect_ratio;
        break;
      case 'audio':
        icon = Icons.audiotrack;
        break;
      case 'subtitle':
        icon = Icons.subtitles;
        break;
      default:
        icon = Icons.info;
    }
    return Icon(icon, color: Colors.white, size: 48);
  }

  Widget _buildOverlayContent() {
    if (_overlayType == 'brightness' || _overlayType == 'volume') {
      return SizedBox(
        width: 150,
        child: LinearProgressIndicator(
          value: _overlayType == 'brightness' ? _brightness : _volume,
          backgroundColor: Colors.white24,
          valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
        ),
      );
    } else if (_overlayType == 'seek') {
      return Text(
        '${_formatDuration(_tempSeekPosition)} / ${_formatDuration(player.state.duration)}',
        style: const TextStyle(
            color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
      );
    } else if (_overlayType.startsWith('seek_')) {
      return const Text(
        '10s',
        style: TextStyle(
            color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
      );
    } else if (_overlayType == 'speed') {
      return Text(
        '${_playbackSpeed}x',
        style: const TextStyle(
            color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
      );
    } else if (_overlayType == 'lock') {
      return Text(
        _isLocked ? 'Locked' : 'Unlocked',
        style: const TextStyle(
            color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
      );
    } else if (_overlayType == 'fit') {
      String mode = 'Contain';
      if (_fitMode == BoxFit.cover) mode = 'Cover';
      if (_fitMode == BoxFit.fill) mode = 'Fill';
      return Text(
        mode,
        style: const TextStyle(
            color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
      );
    } else if (_overlayType == 'audio') {
      return const Text(
        'Audio Track Changed',
        style: TextStyle(
            color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
      );
    } else if (_overlayType == 'subtitle') {
      return const Text(
        'Subtitle Track Changed',
        style: TextStyle(
            color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
      );
    }
    return const SizedBox.shrink();
  }
}
