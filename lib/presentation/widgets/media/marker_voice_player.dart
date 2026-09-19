import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import '../../../data/models/marker_media.dart';
import '../../../services/media/marker_media_service.dart';
import '../../../services/media/marker_media_store.dart';
import '../app_notifications.dart';

/// Compact playback with decorative bars and real position/duration updates.
/// Constructing or rebuilding this widget never creates an audio plugin.
class MarkerVoicePlayer extends StatefulWidget {
  const MarkerVoicePlayer({super.key, required this.media, this.store});

  final MarkerMedia media;
  final MarkerMediaStore? store;

  @override
  State<MarkerVoicePlayer> createState() => _MarkerVoicePlayerState();
}

class _MarkerVoicePlayerState extends State<MarkerVoicePlayer> {
  AudioPlayer? _player;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  Duration _position = Duration.zero;
  Duration? _duration;
  PlayerState _state = PlayerState.stopped;
  bool _busy = false;
  int _generation = 0;

  Duration? get _total =>
      _duration ??
      (widget.media.durationMs == null
          ? null
          : Duration(milliseconds: widget.media.durationMs!));

  @override
  void didUpdateWidget(covariant MarkerVoicePlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.media.fileRef != widget.media.fileRef ||
        oldWidget.store != widget.store) {
      _release();
      _position = Duration.zero;
      _duration = null;
      _state = PlayerState.stopped;
      _busy = false;
    }
  }

  @override
  void dispose() {
    _release();
    super.dispose();
  }

  void _release() {
    _generation++;
    final player = _player;
    _player = null;
    final subscriptions = List<StreamSubscription<dynamic>>.of(_subscriptions);
    _subscriptions.clear();
    unawaited(_cleanup(player, subscriptions));
  }

  Future<void> _cleanup(
    AudioPlayer? player,
    List<StreamSubscription<dynamic>> subscriptions,
  ) async {
    for (final subscription in subscriptions) {
      try {
        await subscription.cancel();
      } catch (_) {
        // The stream may already be detached with the engine.
      }
    }
    try {
      await player?.dispose();
    } catch (_) {
      // Plugin failure must not escape widget disposal.
    }
  }

  bool _isCurrent(int generation) => mounted && generation == _generation;

  void _fail(Object error, int generation) {
    if (!_isCurrent(generation)) return;
    _release();
    setState(() {
      _busy = false;
      _state = PlayerState.stopped;
      _position = Duration.zero;
    });
    AppNotifications.message(
      context,
      MarkerMediaService.describeError(error),
    );
  }

  AudioPlayer _createPlayer(int generation) {
    final player = AudioPlayer();
    _player = player;
    void onError(Object error) => _fail(error, generation);
    _subscriptions.addAll([
      player.onPositionChanged.listen((position) {
        if (_isCurrent(generation)) setState(() => _position = position);
      }, onError: onError),
      player.onDurationChanged.listen((duration) {
        if (_isCurrent(generation) && duration > Duration.zero) {
          setState(() => _duration = duration);
        }
      }, onError: onError),
      player.onPlayerStateChanged.listen((state) {
        if (_isCurrent(generation)) setState(() => _state = state);
      }, onError: onError),
      player.onPlayerComplete.listen((_) {
        if (!_isCurrent(generation)) return;
        setState(() {
          _state = PlayerState.completed;
          _position = _total ?? _position;
        });
      }, onError: onError),
    ]);
    return player;
  }

  Future<void> _toggle() async {
    if (_busy) return;
    final generation = _generation;
    setState(() => _busy = true);
    try {
      final existing = _player;
      if (existing != null && _state == PlayerState.playing) {
        await existing.pause();
      } else if (existing != null && _state == PlayerState.paused) {
        await existing.resume();
      } else {
        final file = await (widget.store ?? MarkerMediaStore())
            .resolve(widget.media.fileRef);
        if (file == null || !await file.exists()) {
          throw StateError('Файл недоступен: сохранена только ссылка');
        }
        if (!_isCurrent(generation)) return;
        // First user-initiated play is the only entry point to native audio.
        final player = existing ?? _createPlayer(generation);
        setState(() => _position = Duration.zero);
        await player.play(DeviceFileSource(file.path));
      }
    } catch (error) {
      _fail(error, generation);
    } finally {
      if (_isCurrent(generation)) setState(() => _busy = false);
    }
  }

  static String _label(Duration? duration) {
    if (duration == null) return '--:--';
    final seconds = duration.inSeconds.clamp(0, 359999);
    return '${(seconds ~/ 60).toString().padLeft(2, '0')}:'
        '${(seconds % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final totalMs = _total?.inMilliseconds ?? 0;
    final progress = totalMs > 0
        ? (_position.inMilliseconds / totalMs).clamp(0.0, 1.0)
        : 0.0;
    final playing = _state == PlayerState.playing;
    return SizedBox(
      height: 52,
      child: Row(
        children: <Widget>[
          IconButton(
            tooltip: playing ? 'Пауза' : 'Прослушать',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 36, height: 40),
            visualDensity: VisualDensity.compact,
            // Keep this gesture owned by the player while loading.
            onPressed: _toggle,
            icon: _busy
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(playing ? Icons.pause : Icons.play_arrow, size: 24),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Semantics(
                  label: 'Голосовая заметка',
                  value: '${_label(_position)} из ${_label(_total)}',
                  child: SizedBox(
                    height: 24,
                    child: CustomPaint(
                      painter: _WaveformPainter(
                        progress: progress,
                        active: theme.colorScheme.primary,
                        inactive: theme.colorScheme.outlineVariant,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: <Widget>[
                    Icon(Icons.graphic_eq,
                        size: 12, color: theme.colorScheme.onSurfaceVariant),
                    const SizedBox(width: 3),
                    Expanded(
                      child: Text(
                        '${_label(_position)} / ${_label(_total)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  const _WaveformPainter({
    required this.progress,
    required this.active,
    required this.inactive,
  });

  final double progress;
  final Color active;
  final Color inactive;

  // Deliberately decorative: this is not an analysis of the recording.
  static const _heights = [0.3, 0.6, 0.9, 0.45, 0.7, 1.0, 0.5, 0.8, 0.4];

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0) return;
    final count = (size.width / 5).floor().clamp(1, 48);
    final step = size.width / count;
    final paint = Paint();
    for (var i = 0; i < count; i++) {
      final height = size.height * _heights[i % _heights.length];
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
            i * step, (size.height - height) / 2, step * 0.55, height),
        const Radius.circular(2),
      );
      canvas.drawRRect(rect, paint..color = inactive);
      canvas.save();
      canvas.clipRect(Rect.fromLTWH(0, 0, size.width * progress, size.height));
      canvas.drawRRect(rect, paint..color = active);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.active != active ||
      oldDelegate.inactive != inactive;
}
