import 'package:audio_service/audio_service.dart';
import 'package:hive/hive.dart';

import '../../domain/repositories/download_repository.dart';
import '../../models/media_Item_builder.dart';
import '../../services/constant.dart';

class HiveDownloadRepository implements DownloadRepository {
  Box get _box => Hive.box(BoxNames.songDownloads);

  /// True only when the entry names a local file.
  ///
  /// Key presence alone is not enough: downloads used to sync between devices,
  /// and the payload sanitizer strips local paths, so a device could hold a
  /// download record with no `url` and no audio behind it. Those must read as
  /// not-downloaded, or the UI badges them as offline-ready and the downloader
  /// refuses to fetch them. Existence on disk is deliberately not checked here
  /// — this runs per song while rendering lists, and a temporarily unreachable
  /// file (missing storage permission, unmounted SD card) is handled further
  /// down, where playback falls back to streaming.
  static bool hasLocalFile(dynamic entry) =>
      entry is Map &&
      entry['url'] is String &&
      (entry['url'] as String).isNotEmpty;

  @override
  Future<bool> containsDownload(String songId) async =>
      hasLocalFile(_box.get(songId));

  @override
  Future<dynamic> getDownloadJson(String songId) async => _box.get(songId);

  @override
  Future<Map<dynamic, dynamic>> getAllDownloadJsonEntries() async =>
      Map<dynamic, dynamic>.from(_box.toMap());

  @override
  Future<MediaItem?> getDownloadedSong(String songId) async {
    final value = _box.get(songId);
    return value == null ? null : MediaItemBuilder.fromJson(value);
  }

  @override
  Future<void> saveDownloadedSong(MediaItem song) =>
      _box.put(song.id, MediaItemBuilder.toJson(song));

  @override
  Future<void> saveDownloadedSongJson(
    String songId,
    Map<String, dynamic> json,
  ) => _box.put(songId, json);

  @override
  Future<void> deleteDownloadedSong(String songId) => _box.delete(songId);

  @override
  Future<List<String>> getDownloadedSongFilePaths() async => _box.values
      .map((item) => item is Map ? item['url'] : null)
      .whereType<String>()
      .toList();

  @override
  Future<void> updateDownloadedSongJson(
    String songId,
    Map<String, dynamic> json,
  ) => _box.put(songId, json);
}
