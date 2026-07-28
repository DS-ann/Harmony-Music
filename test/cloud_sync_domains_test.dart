import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/data/repositories/cloud_sync_repository.dart';
import 'package:harmonymusic/data/repositories/hive_download_repository.dart';
import 'package:harmonymusic/data/repositories/hive_library_repository.dart';
import 'package:harmonymusic/services/constant.dart';
import 'package:hive/hive.dart';

void main() {
  group('box to sync domain mapping', () {
    test('each synced box reports its own domain', () {
      expect(CloudSyncRepository.domainForBox(BoxNames.appPrefs), 'settings');
      expect(CloudSyncRepository.domainForBox(BoxNames.libFav), 'favourites');
      expect(
        CloudSyncRepository.domainForBox(BoxNames.libRP),
        'recentlyPlayed',
      );
      expect(
        CloudSyncRepository.domainForBox(BoxNames.libraryPlaylists),
        'playlists',
      );
      expect(
        CloudSyncRepository.domainForBox(BoxNames.libraryAlbums),
        'albums',
      );
      expect(
        CloudSyncRepository.domainForBox(BoxNames.libraryArtists),
        'artists',
      );
      expect(
        CloudSyncRepository.domainForBox(BoxNames.librarySearches),
        'savedSearches',
      );
      expect(
        CloudSyncRepository.domainForBox(BoxNames.searchQuery),
        'searchHistory',
      );
      expect(
        CloudSyncRepository.domainForBox(BoxNames.blacklistedPlaylist),
        'blacklistedPlaylists',
      );
    });

    test('a per-playlist song box maps to the playlist songs domain', () {
      // Those boxes are named after the playlist id, so anything unrecognised
      // is playlist contents rather than an error.
      expect(
        CloudSyncRepository.domainForBox('PL_local_1753624'),
        'playlistSongs',
      );
    });

    test('settings and songs never share a domain', () {
      expect(
        CloudSyncRepository.domainForBox(BoxNames.appPrefs),
        isNot(CloudSyncRepository.domainForBox(BoxNames.libFav)),
      );
    });
  });

  group('downloads stay on the device that made them', () {
    late Directory hiveDir;

    setUp(() async {
      hiveDir = await Directory.systemTemp.createTemp('download_local_test_');
      Hive.init(hiveDir.path);
      await Hive.openBox(BoxNames.songDownloads);
    });

    tearDown(() async {
      await Hive.close();
      await hiveDir.delete(recursive: true);
    });

    test('a record with a local path counts as downloaded', () async {
      final box = Hive.box(BoxNames.songDownloads);
      await box.put('song-1', {
        'videoId': 'song-1',
        'title': 'Song',
        'url': '/storage/emulated/0/Music/Song.m4a',
      });

      expect(await HiveDownloadRepository().containsDownload('song-1'), isTrue);
      expect(await HiveLibraryRepository().isDownloaded('song-1'), isTrue);
    });

    test('a record inherited from another device does not', () async {
      // Downloads used to sync, and the payload sanitizer strips local paths,
      // so the arriving record names no file this device can play.
      final box = Hive.box(BoxNames.songDownloads);
      await box.put('song-2', {'videoId': 'song-2', 'title': 'Song'});

      expect(
        await HiveDownloadRepository().containsDownload('song-2'),
        isFalse,
      );
      expect(await HiveLibraryRepository().isDownloaded('song-2'), isFalse);
    });

    test('purging removes only the path-less records', () async {
      final box = Hive.box(BoxNames.songDownloads);
      await box.put('keep', {'videoId': 'keep', 'url': '/music/keep.m4a'});
      await box.put('drop', {'videoId': 'drop'});
      await box.put('drop-empty', {'videoId': 'drop-empty', 'url': ''});

      final removed = await HiveLibraryRepository()
          .purgeDownloadsWithoutLocalFile();

      expect(removed, 2);
      expect(box.containsKey('keep'), isTrue);
      expect(box.containsKey('drop'), isFalse);
      expect(box.containsKey('drop-empty'), isFalse);
    });
  });
}
