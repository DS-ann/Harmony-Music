import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers/auth_providers.dart';
import '../../app/providers/controller_providers.dart';
import '../../l10n/l10n.dart';
import '../../app/providers/service_providers.dart';
import '../../services/cloud/harmony_cloud_client.dart';
import '../player/player_controller.dart';

Future<void> showCloudDevicesSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _CloudDevicesSheet(),
    );

class _CloudDevicesSheet extends ConsumerStatefulWidget {
  const _CloudDevicesSheet();

  @override
  ConsumerState<_CloudDevicesSheet> createState() => _CloudDevicesSheetState();
}

class _CloudDevicesSheetState extends ConsumerState<_CloudDevicesSheet> {
  late Future<List<CloudPlaybackDevice>> _devices;

  /// The device a handoff is currently in flight to, if any.
  String? _handingOffTo;

  @override
  void initState() {
    super.initState();
    _loadDevices();
  }

  void _loadDevices() {
    _devices = ref.read(authControllerProvider).playbackDevices();
  }

  void _retry() => setState(_loadDevices);

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 24),
      child: FutureBuilder<List<CloudPlaybackDevice>>(
        future: _devices,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const SizedBox(
              height: 160,
              child: Center(child: CircularProgressIndicator()),
            );
          }
          if (snapshot.hasError) {
            return SizedBox(
              height: 190,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    context.l10n.playOnDevice,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      context.l10n.deviceControlUnavailable,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: _retry,
                    icon: const Icon(Icons.refresh),
                    label: Text(context.l10n.retry),
                  ),
                ],
              ),
            );
          }
          final loadedDevices = snapshot.data;
          if (loadedDevices == null) {
            return const SizedBox.shrink();
          }
          final devices = loadedDevices;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(
                  context.l10n.playOnDevice,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              if (devices.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(context.l10n.noOtherDevices),
                ),
              for (final device in devices)
                ListTile(
                  leading: Icon(
                    device.platform == 'windows'
                        ? Icons.computer
                        : Icons.phone_android,
                    color: device.isAudioTarget
                        ? Colors.blueAccent
                        : device.presence == 'unavailable'
                        ? Theme.of(context).disabledColor
                        : null,
                  ),
                  title: Text(
                    device.isCurrentDevice
                        ? '${device.name} (This device)'
                        : device.name,
                    style: device.isAudioTarget
                        ? const TextStyle(color: Colors.blueAccent)
                        : null,
                  ),
                  subtitle: Text(
                    device.isCurrentDevice &&
                            ref.read(cloudPlaybackReceiverProvider).isEngaged
                        // The exit affordance: your own row, while synced.
                        ? context.l10n.tapToLeaveSync
                        : device.isAudioTarget
                        ? 'Playing here'
                        : _presenceLabel(context, device.presence),
                  ),
                  // A handoff is not instant: the target has to resolve the
                  // song before it can start. Show that it is working rather
                  // than leaving the row looking inert.
                  trailing: _handingOffTo == device.deviceId
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : null,
                  enabled:
                      device.presence != 'unavailable' && _handingOffTo == null,
                  onTap:
                      device.presence == 'unavailable' || _handingOffTo != null
                      ? null
                      : device.isCurrentDevice
                      ? () => _leaveSync(context)
                      : () => _handoff(context, device),
                ),
            ],
          );
        },
      ),
    ),
  );

  /// Tapping your own device row ends the shared session for every participant.
  /// Playback is paused on both devices before their roles are cleared.
  Future<void> _leaveSync(BuildContext context) async {
    final receiver = ref.read(cloudPlaybackReceiverProvider);
    if (!receiver.isEngaged) return;
    // Close the sheet first, while its route is provably the top one. Leaving
    // sync now does real work — it adopts the session's song onto this device,
    // which can take a second or two to resolve a stream — and popping after
    // that await pops whatever happens to be on top by then. That emptied
    // go_router's match list, tripped its assert, and tore the navigator down
    // to a black screen. Nothing below needs the widget to still be alive.
    Navigator.of(context).pop();
    await receiver.leaveSync();
  }

  String _presenceLabel(BuildContext context, String presence) =>
      switch (presence) {
        'online' => context.l10n.deviceOnline,
        'background' => context.l10n.deviceBackground,
        _ => context.l10n.deviceUnavailable,
      };

  Future<void> _handoff(
    BuildContext context,
    CloudPlaybackDevice device,
  ) async {
    final player = ref.read(playerControllerProvider);
    final current = player.currentSong.value;
    if (current == null) return;
    var accepted = false;
    setState(() => _handingOffTo = device.deviceId);
    try {
      // `loading` counts as playing: handing off while the source is still
      // buffering used to send playing:false, and the target would load the
      // song, seek to the right position, and then just sit there.
      final wasPlaying =
          player.buttonState.value == PlayButtonState.playing ||
          player.buttonState.value == PlayButtonState.loading;
      final position = player.progressBarStatus.value.current.inMilliseconds;
      await player.pause();
      final commandService = ref.read(playbackCommandServiceProvider);
      final localQueue = player.currentQueue.isEmpty
          ? [current]
          : player.currentQueue;
      final sessionIds = ref
          .read(cloudPlaybackReceiverProvider)
          .sessionQueueIds;
      // Prefer the cloud's queue only when it is genuinely richer AND still
      // contains what we are about to hand off. While acting as the audio
      // target the local handler briefly holds just the loaded song, so the
      // cloud copy is the fuller one — but once the user picks a different
      // song the cloud queue is stale, and publishing it would hand over the
      // previously played track instead of the selected one.
      final queueIds =
          sessionIds != null &&
              sessionIds.contains(current.id) &&
              sessionIds.length > localQueue.length
          ? sessionIds
          : null;
      final sessionId = await commandService.startSharedSession(
        targetDeviceId: device.deviceId,
        queue: localQueue,
        index: player.currentSongIndex.value < 0
            ? 0
            : player.currentSongIndex.value,
        positionMs: position,
        playing: wasPlaying,
        queueVideoIds: queueIds,
        currentVideoId: current.id,
      );
      accepted = sessionId != null;
      if (accepted) {
        // Seed the mirror from what was just on screen: a brand-new session's
        // persisted progress is still zero, so waiting for the server round
        // trip showed a bar reset to 0:00 and a paused button instead of the
        // handed-off position with a pause control.
        ref
            .read(cloudPlaybackReceiverProvider)
            .adoptInitiatedHandoff(
              queue: localQueue,
              queueIds: queueIds ?? localQueue.map((s) => s.id).toList(),
              currentSongId: current.id,
              positionMs: position,
            );
      }
    } catch (_) {
      accepted = false;
    }
    if (accepted) {
      // The snapshot broadcast may have arrived before this device flipped
      // into controller mode and been ignored; pull the session explicitly so
      // the mirror UI stays consistent with the cloud copy.
      unawaited(ref.read(cloudPlaybackReceiverProvider).refreshSession());
    }
    if (mounted) setState(() => _handingOffTo = null);
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    if (accepted) {
      if (!context.mounted) return;
      // Only dismiss while this sheet is still the top route. Starting a
      // session is a network round trip, and popping blind afterwards can take
      // out whatever replaced it — which empties go_router's match list and
      // blacks out the app. A sheet left open is a far cheaper failure.
      if (ModalRoute.of(context)?.isCurrent ?? false) {
        Navigator.of(context).pop();
      }
    }
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          accepted
              ? context.l10n.handoffRequested
              : context.l10n.deviceControlUnavailable,
        ),
      ),
    );
  }
}
