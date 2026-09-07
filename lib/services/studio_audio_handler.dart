import 'package:audio_service/audio_service.dart';

/// Lock-screen / Control Center / notification transport.
class StudioAudioHandler extends BaseAudioHandler {
  StudioAudioHandler({
    required this.onPlay,
    required this.onPause,
    required this.onStop,
  });

  final void Function() onPlay;
  final void Function() onPause;
  final void Function() onStop;

  void setProject(String name, {required bool playing}) {
    mediaItem.add(
      MediaItem(
        id: 'layerstudio',
        album: 'LayerStudio',
        title: name,
        artist: 'LayerStudio',
        playable: true,
      ),
    );
    playbackState.add(
      playbackState.value.copyWith(
        playing: playing,
        controls: [
          MediaControl.stop,
          playing ? MediaControl.pause : MediaControl.play,
        ],
        androidCompactActionIndices: const [0, 1],
        processingState: AudioProcessingState.ready,
        systemActions: const {MediaAction.play, MediaAction.pause, MediaAction.stop},
      ),
    );
  }

  @override
  Future<void> play() async => onPlay();

  @override
  Future<void> pause() async => onPause();

  @override
  Future<void> stop() async => onStop();
}
