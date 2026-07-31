import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/cloud/harmony_cloud_client.dart';

void main() {
  test('device removal uses an authenticated account-scoped DELETE', () async {
    final adapter = _RecordingAdapter();
    final dio = Dio()..httpClientAdapter = adapter;
    final client = HarmonyCloudClient(
      dio: dio,
      accessToken: () async => 'test-token',
      baseUrl: 'https://cloud.example.test/cloud/',
    );

    await client.removePlaybackDevice('device-123');

    expect(adapter.request?.method, 'DELETE');
    expect(adapter.request?.uri.path, '/cloud/v1/devices/device-123');
    expect(adapter.request?.headers['Authorization'], 'Bearer test-token');
  });
}

class _RecordingAdapter implements HttpClientAdapter {
  RequestOptions? request;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    request = options;
    return ResponseBody.fromBytes(const [], 204);
  }

  @override
  void close({bool force = false}) {}
}
