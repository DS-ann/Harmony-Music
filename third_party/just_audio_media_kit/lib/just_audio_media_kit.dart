library just_audio_media_kit;

import 'package:flutter/services.dart';
import 'package:just_audio_media_kit/mediakit_player.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:logging/logging.dart';
import 'package:media_kit/media_kit.dart';

typedef MediaKitDiagnosticCallback = void Function(
    String category, String message);

class JustAudioMediaKit extends JustAudioPlatform {
  static MPVLogLevel mpvLogLevel = MPVLogLevel.error;
  static int bufferSize = 32 * 1024 * 1024;
  static String title = 'JustAudioMediaKit';
  static List<String> protocolWhitelist = const [
    'udp',
    'rtp',
    'tcp',
    'tls',
    'data',
    'file',
    'http',
    'https',
    'crypto',
  ];
  static MediaKitDiagnosticCallback? diagnosticCallback;

  static final _logger = Logger('JustAudioMediaKit');
  final Map<String, MediaKitPlayer> _players = {};

  static void registerWith() {
    JustAudioPlatform.instance = JustAudioMediaKit();
  }

  @override
  Future<AudioPlayerPlatform> init(InitRequest request) async {
    MediaKit.ensureInitialized();
    if (_players.containsKey(request.id)) {
      throw PlatformException(
        code: 'error',
        message: 'Player ${request.id} already exists!',
      );
    }
    _logger.fine('instantiating new player ${request.id}');
    final player = MediaKitPlayer(request.id);
    _players[request.id] = player;
    await player.initializeAudioOutput();
    return player;
  }

  @override
  Future<DisposePlayerResponse> disposePlayer(
      DisposePlayerRequest request) async {
    await _players.remove(request.id)?.release();
    return DisposePlayerResponse();
  }

  @override
  Future<DisposeAllPlayersResponse> disposeAllPlayers(
    DisposeAllPlayersRequest request,
  ) async {
    await Future.wait(_players.values.map((player) => player.release()));
    _players.clear();
    return DisposeAllPlayersResponse();
  }
}
