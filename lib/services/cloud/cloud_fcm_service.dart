import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import '../../utils/runtime_platform.dart';

/// FCM only carries an opaque command id. Playback data is always fetched from
/// Harmony Cloud using the signed-in device's authenticated session.
class CloudFcmService {
  CloudFcmService(this._registerToken);

  final Future<void> Function(String token) _registerToken;
  StreamSubscription<String>? _tokenSubscription;

  Future<void> start() async {
    if (!RuntimePlatform.isAndroid) return;
    try {
      await Firebase.initializeApp();
      final messaging = FirebaseMessaging.instance;
      final token = await messaging.getToken();
      if (token != null && token.isNotEmpty) await _registerToken(token);
      await _tokenSubscription?.cancel();
      _tokenSubscription = messaging.onTokenRefresh.listen((token) {
        unawaited(_registerToken(token));
      });
    } catch (_) {
      // FCM is optional for a device: no registration means it is not shown as
      // background-reachable. Do not expose Firebase configuration details.
    }
  }

  Future<void> dispose() async => _tokenSubscription?.cancel();
}
