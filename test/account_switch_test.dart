import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/data/repositories/cloud_sync_repository.dart';
import 'package:harmonymusic/domain/repositories/playlist_repository.dart';
import 'package:harmonymusic/models/playlist.dart';
import 'package:harmonymusic/services/constant.dart';
import 'package:hive/hive.dart';

// Nothing recorded which account a device's library belonged to, so signing
// into a second account inherited the first one's library and reinterpreted its
// sync bookkeeping — and the next fingerprint reset would have uploaded one
// account's music into the other.
void main() {
  late Directory hiveDir;
  late CloudSyncRepository repository;

  setUp(() async {
    hiveDir = await Directory.systemTemp.createTemp('account_switch_test_');
    Hive.init(hiveDir.path);
    for (final box in const [
      BoxNames.appPrefs,
      BoxNames.libFav,
      BoxNames.libRP,
      BoxNames.libraryPlaylists,
      BoxNames.libraryAlbums,
      BoxNames.libraryArtists,
      BoxNames.librarySearches,
      BoxNames.blacklistedPlaylist,
      BoxNames.searchQuery,
      BoxNames.songDownloads,
      BoxNames.songsCache,
      BoxNames.cloudSyncOutbox,
      BoxNames.cloudSyncState,
    ]) {
      await Hive.openBox(box);
    }
    repository = CloudSyncRepository(_NoPlaylists());
  });

  tearDown(() async {
    await Hive.close();
    await hiveDir.delete(recursive: true);
  });

  test('forgetting an account clears its library but keeps the audio', () async {
    await Hive.box(BoxNames.libFav).put('song', {'videoId': 'song'});
    await Hive.box(
      BoxNames.libraryAlbums,
    ).put('MPREb_album', {'browseId': 'MPREb_album', 'title': 'Album'});
    final albumSongs = await Hive.openBox('MPREb_album');
    await albumSongs.add({'videoId': 'song'});
    await Hive.box(BoxNames.searchQuery).add('a search');
    await Hive.box(BoxNames.cloudSyncState).put('fingerprint:LIBFAV:x', 'abc');
    await Hive.box(BoxNames.cloudSyncOutbox).put(1, {'eventId': 'e'});
    await Hive.box(BoxNames.appPrefs).put(PrefKeys.cloudCheckpoint, 188);
    await Hive.box(BoxNames.appPrefs).put(PrefKeys.cloudDeviceId, 'device-1');
    // Device-local: must survive, since the filter decides visibility and a
    // switch must not cost a multi-gigabyte re-download.
    await Hive.box(
      BoxNames.songDownloads,
    ).put('song', {'videoId': 'song', 'url': '/music/song.m4a'});
    await Hive.box(BoxNames.songsCache).put('cached', {'videoId': 'cached'});

    await repository.forgetAccountLibrary();

    expect(Hive.box(BoxNames.libFav).isEmpty, isTrue);
    expect(Hive.box(BoxNames.libraryAlbums).isEmpty, isTrue);
    expect(Hive.box('MPREb_album').isEmpty, isTrue);
    expect(Hive.box(BoxNames.searchQuery).isEmpty, isTrue);
    expect(Hive.box(BoxNames.cloudSyncState).isEmpty, isTrue);
    expect(Hive.box(BoxNames.cloudSyncOutbox).isEmpty, isTrue);

    // Without this the new account's history is filtered out entirely: changes
    // are `revision > checkpoint` and the server's sequence spans accounts.
    expect(Hive.box(BoxNames.appPrefs).get(PrefKeys.cloudCheckpoint), 0);

    expect(Hive.box(BoxNames.appPrefs).get(PrefKeys.cloudDeviceId), 'device-1');
    expect(Hive.box(BoxNames.songDownloads).containsKey('song'), isTrue);
    expect(Hive.box(BoxNames.songsCache).containsKey('cached'), isTrue);
  });

  test('a wiped device re-uploads everything it still holds', () async {
    // The fingerprints go with the wipe, so the next scan treats whatever
    // remains as new rather than assuming the server already has it.
    await Hive.box(BoxNames.cloudSyncState).put('fingerprint:LIBFAV:x', 'abc');
    await repository.forgetAccountLibrary();
    await Hive.box(BoxNames.libFav).put('fresh', {'videoId': 'fresh'});

    final events = await repository.scan();

    expect(events.any((event) => event.entityId.startsWith('LIBFAV:')), isTrue);
  });
}

class _NoPlaylists implements PlaylistRepository {
  @override
  Future<List<Playlist>> getPlaylists() async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used here');
}
