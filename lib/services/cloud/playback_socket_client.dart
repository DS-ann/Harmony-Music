import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:web_socket_channel/io.dart';

import '../../utils/helper.dart';
import '../constant.dart';
import '../crash_diagnostics_service.dart';

/// Connection state, surfaced so the UI can show an honest "reconnecting"
/// indicator. With no polling fallback, a dead socket means no remote control at
/// all — it must never fail silently.
enum PlaybackSocketStatus { disconnected, connecting, connected }

abstract interface class PlaybackSocketTransport {
  Stream<Map<String, dynamic>> get frames;

  Stream<PlaybackSocketStatus> get status;

  PlaybackSocketStatus get currentStatus;

  Future<void> connect(String deviceId);

  void send(Map<String, Object?> frame);

  Future<void> dispose();
}

/// The single realtime channel to Harmony Cloud.
///
/// Replaces a 1s REST poll of `GET /playback/session` plus
/// `GET /playback/commands` on every device. Auth rides on the standard
/// `Authorization` header of the upgrade request, which dart:io sockets support,
/// so no token ever appears in a URL.
class PlaybackSocketClient implements PlaybackSocketTransport {
  PlaybackSocketClient({
    required Future<String?> Function() accessToken,
    required String baseUrl,
  }) : _accessToken = accessToken,
       _baseUrl = baseUrl;

  final Future<String?> Function() _accessToken;
  final String _baseUrl;

  final _frames = StreamController<Map<String, dynamic>>.broadcast();
  final _status = StreamController<PlaybackSocketStatus>.broadcast();

  IOWebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _reconnect;
  Timer? _heartbeat;
  String? _deviceId;
  bool _closed = false;
  int _attempt = 0;

  Stream<Map<String, dynamic>> get frames => _frames.stream;
  Stream<PlaybackSocketStatus> get status => _status.stream;

  PlaybackSocketStatus get currentStatus => _currentStatus;
  PlaybackSocketStatus _currentStatus = PlaybackSocketStatus.disconnected;

  static const _heartbeatInterval = Duration(seconds: 30);
  static const _maximumBackoff = Duration(seconds: 30);

  Future<void> connect(String deviceId) async {
    _deviceId = deviceId;
    _closed = false;
    await _open();
  }

  Future<void> _open() async {
    if (_closed || _deviceId == null) return;
    _reconnect?.cancel();
    _setStatus(PlaybackSocketStatus.connecting);
    try {
      final token = await _accessToken();
      final socket = await WebSocket.connect(
        _socketUri(_deviceId!).toString(),
        headers: {
          if (token != null && token.isNotEmpty)
            'Authorization': 'Bearer $token',
        },
      );
      if (_closed) {
        await socket.close();
        return;
      }
      final channel = IOWebSocketChannel(socket);
      _channel = channel;
      _attempt = 0;
      printINFO(
        'socket connected device=$_deviceId',
        tag: LogTags.cloudPlayback,
      );
      _setStatus(PlaybackSocketStatus.connected);
      _subscription = channel.stream.listen(
        _onFrame,
        onError: (_) => _scheduleReconnect(),
        onDone: _scheduleReconnect,
        cancelOnError: true,
      );
      _heartbeat?.cancel();
      _heartbeat = Timer.periodic(
        _heartbeatInterval,
        (_) => send({'type': 'ping'}),
      );
    } catch (error, stackTrace) {
      CrashDiagnosticsService.instance.record(
        'cloud-playback',
        'Playback socket connect failed',
        error: error,
        stackTrace: stackTrace,
      );
      _scheduleReconnect();
    }
  }

  void _onFrame(dynamic message) {
    if (message is! String) return;
    try {
      final decoded = jsonDecode(message);
      if (decoded is Map<String, dynamic>) _frames.add(decoded);
    } on FormatException {
      // A malformed frame is not worth dropping the connection over.
    }
  }

  void send(Map<String, Object?> frame) {
    final channel = _channel;
    if (channel == null || _currentStatus != PlaybackSocketStatus.connected)
      return;
    try {
      channel.sink.add(jsonEncode(frame));
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_closed) return;
    _teardown();
    _setStatus(PlaybackSocketStatus.disconnected);
    // Exponential backoff capped at 30s, so a server outage does not turn every
    // installed device into a retry storm.
    final delay = Duration(
      milliseconds: (500 * (1 << _attempt.clamp(0, 6))).clamp(
        500,
        _maximumBackoff.inMilliseconds,
      ),
    );
    _attempt++;
    _reconnect?.cancel();
    _reconnect = Timer(delay, () => unawaited(_open()));
  }

  void _setStatus(PlaybackSocketStatus status) {
    if (_currentStatus == status) return;
    _currentStatus = status;
    if (!_status.isClosed) _status.add(status);
  }

  void _teardown() {
    _heartbeat?.cancel();
    _heartbeat = null;
    unawaited(_subscription?.cancel());
    _subscription = null;
    unawaited(_channel?.sink.close());
    _channel = null;
  }

  Uri _socketUri(String deviceId) {
    final base = Uri.parse(_baseUrl).resolve('v1/playback/socket');
    // Rebuild rather than `replace(scheme: ...)`. Uri.port reports the default
    // port for the *current* scheme, so swapping https->wss through replace
    // carries a port across schemes and emits `host:0` — which is what the
    // connect failures in the diagnostics log were reporting themselves as.
    return Uri(
      scheme: base.scheme == 'https' ? 'wss' : 'ws',
      host: base.host,
      port: base.hasPort ? base.port : null,
      path: base.path,
      queryParameters: {'deviceId': deviceId},
    );
  }

  Future<void> dispose() async {
    _closed = true;
    _reconnect?.cancel();
    _teardown();
    _setStatus(PlaybackSocketStatus.disconnected);
    await _frames.close();
    await _status.close();
  }
}
