import 'harmony_cloud_client.dart';

/// Cloud operations used by cross-device playback.
///
/// Kept separate from library synchronization so two deterministic device
/// endpoints can be connected in integration tests without a live server.
abstract interface class CloudPlaybackGateway {
  String get deviceId;

  Future<CloudPlaybackSession?> playbackSession();

  Future<String> startPlaybackSession({
    required String targetDeviceId,
    required Map<String, Object?> state,
  });

  Future<void> switchPlaybackTarget({
    required String targetDeviceId,
    required Map<String, Object?> state,
  });

  Future<void> sendSessionCommand({
    required String targetDeviceId,
    required String type,
    required Map<String, Object?> payload,
  });

  Future<void> updatePlaybackSessionState(Map<String, Object?> state);

  Future<void> endPlaybackSession();

  Future<List<CloudPlaybackCommand>> pendingPlaybackCommands();

  Future<void> acknowledgePlaybackCommand({
    required String commandId,
    required bool applied,
  });
}
