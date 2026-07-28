import 'dart:io';

import '../domain/repositories/download_repository.dart';
import '../domain/repositories/library_repository.dart';
import '../domain/repositories/settings_repository.dart';
import '../domain/repositories/song_cache_repository.dart';
import '/ui/screens/Library/library_controller.dart';
import 'package:path_provider/path_provider.dart';
import '../services/constant.dart';
import '../services/utils.dart';
import 'helper.dart';

Future<void> startHouseKeeping({
  required SongCacheRepository songCacheRepository,
  required DownloadRepository downloadRepository,
  required LibraryRepository libraryRepository,
  required SettingsRepository settingsRepository,
  required LibrarySongsController librarySongsController,
}) async {
  await removeExpiredSongsUrlFromDb(
    songCacheRepository: songCacheRepository,
    downloadRepository: downloadRepository,
    libraryRepository: libraryRepository,
    librarySongsController: librarySongsController,
  );
  await removeDownloadsWithoutLocalFile(libraryRepository: libraryRepository);
  await removeThinCachedSongs(
    songCacheRepository: songCacheRepository,
    settingsRepository: settingsRepository,
  );
}

/// Drops cached songs that predate rich Resolver metadata, once.
///
/// The song cache is consulted before any network source, so a video-shaped
/// answer — channel as artist, letterboxed thumbnail, no album — stayed
/// authoritative forever and no later lookup could improve it. Clearing those
/// entries lets them resolve again now that the Resolver reads YouTube Music.
///
/// Guarded by a stored version rather than run every launch: after the purge a
/// song with genuinely no album (a plain video) still has no album id, and
/// re-purging it every time would evict it from the cache forever.
/// The current one-time thin-cache purge, bumped whenever a future release
/// needs another pass. Exposed so tests can pre-seed past it — otherwise any
/// cached song seeded without an `album.id` (most hand-written fixtures) is
/// silently purged the first time `startHouseKeeping` runs.
const thinCachePurgeVersion = 1;

Future<void> removeThinCachedSongs({
  required SongCacheRepository songCacheRepository,
  required SettingsRepository settingsRepository,
}) async {
  if (settingsRepository.getSongCachePurgeVersion() >= thinCachePurgeVersion) {
    return;
  }
  final removed = await songCacheRepository.purgeSongsWithoutAlbumId();
  await settingsRepository.setSongCachePurgeVersion(thinCachePurgeVersion);
  if (removed > 0) {
    printINFO(
      "Dropped $removed cached song(s) with no album id so they re-resolve",
      tag: LogTags.musicService,
    );
  }
}

/// Clears out download records inherited from another device back when
/// downloads still synced. They carry no local path, so this device shows them
/// as available offline while having no audio for them, and the downloader
/// skips re-fetching anything already recorded as downloaded.
Future<void> removeDownloadsWithoutLocalFile({
  required LibraryRepository libraryRepository,
}) async {
  final removed = await libraryRepository.purgeDownloadsWithoutLocalFile();
  if (removed > 0) {
    printINFO(
      "Removed $removed download record(s) with no local file",
      tag: LogTags.downloader,
    );
  }
}

Future<void> removeExpiredSongsUrlFromDb({
  required SongCacheRepository songCacheRepository,
  required DownloadRepository downloadRepository,
  required LibraryRepository libraryRepository,
  required LibrarySongsController librarySongsController,
}) async {
  try {
    final entries = await songCacheRepository.getAllStreamCacheEntries();
    for (final entry in entries.entries) {
      final songUrlKey = entry.key;
      if (shouldDeleteStreamCacheEntry(entry.value)) {
        await songCacheRepository.deleteStreamCacheEntry(songUrlKey);
      }
    }
  } catch (e) {
    printERROR("Error in removeExpiredSongsUrlFromDb: $e");
  } finally {
    await removeDeletedOfflineSongsFromDb(
      downloadRepository: downloadRepository,
      libraryRepository: libraryRepository,
      librarySongsController: librarySongsController,
    );
  }
}

bool shouldDeleteStreamCacheEntry(dynamic cacheValue) {
  if (cacheValue is Map) {
    final audioEntries = [
      cacheValue['lowQualityAudio'],
      cacheValue['highQualityAudio'],
    ];
    final urls = <String>[];
    for (final audio in audioEntries) {
      final url = audio is Map ? audio['url'] : null;
      if (url is! String) return true;
      urls.add(url);
    }
    return urls.every((url) => isExpired(url: url));
  }

  if (cacheValue is List && cacheValue.isNotEmpty) {
    final streamData = cacheValue.length > 1 ? cacheValue[1] : null;
    final url = streamData is Map ? streamData['url'] : null;
    return url is! String || isExpired(url: url);
  }

  return true;
}

Future<void> removeDeletedOfflineSongsFromDb({
  required DownloadRepository downloadRepository,
  required LibraryRepository libraryRepository,
  required LibrarySongsController librarySongsController,
}) async {
  final supportDir = (await getApplicationSupportDirectory()).path;
  try {
    final downloadedSongs = await libraryRepository.getDownloadedSongs();
    for (final downloadedSong in downloadedSongs) {
      final songKey = downloadedSong.id;
      final songUrl = downloadedSong.extras?['url'];
      if (songUrl is! String) continue;
      if (await File(songUrl).exists() == false) {
        await downloadRepository.deleteDownloadedSong(songKey);
        await librarySongsController.removeSong(downloadedSong, true);
        final thumbNailPath = "$supportDir/thumbnails/$songKey.png";
        if (await File(thumbNailPath).exists()) {
          await File(thumbNailPath).delete();
        }
      }
    }
  } catch (e) {
    printERROR("Error in removeDeletedOfflineSongsFromDb: $e");
  }
}
