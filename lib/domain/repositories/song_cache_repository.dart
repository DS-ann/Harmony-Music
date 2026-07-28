import 'package:audio_service/audio_service.dart';

import '../../models/hm_streaming_data.dart';

abstract class SongCacheRepository {
  Future<bool> containsCachedSong(String songId);
  Future<MediaItem?> getCachedSong(String songId);
  Future<dynamic> getCachedSongJson(String songId);
  Future<void> saveCachedSong(MediaItem song);
  Future<void> saveCachedSongJson(String songId, Map<String, dynamic> json);
  Future<void> deleteCachedSong(String songId);

  /// Drops cached songs with no album id so they re-resolve, returning how many
  /// went. Those entries predate rich Resolver metadata and would otherwise win
  /// over it forever, since the cache is consulted first.
  Future<int> purgeSongsWithoutAlbumId();
  Future<dynamic> getStreamCacheEntry(String songId);
  Future<HMStreamingData?> getStreamInfo(String songId, int qualityIndex);
  Future<void> saveStreamCacheEntry(String songId, dynamic value);
  Future<void> deleteStreamCacheEntry(String songId);
  Future<void> clearStreamCache();
  Future<Map<String, dynamic>> getAllStreamCacheEntries();
}
