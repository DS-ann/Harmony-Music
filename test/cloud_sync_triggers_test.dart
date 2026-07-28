import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/data/repositories/cloud_sync_repository.dart';
import 'package:harmonymusic/domain/repositories/playlist_repository.dart';
import 'package:harmonymusic/models/playlist.dart';
import 'package:harmonymusic/services/constant.dart';
import 'package:hive/hive.dart';

// Regression: sync only ever ran at app start, so liking a song wrote to Hive
// and stopped there — the change did not reach the server until the app was
// relaunched, and other devices never learned about it at all.
void main() {
  late Directory hiveDir;
  late CloudSyncRepository repository;

  setUp(() async {
    hiveDir = await Directory.systemTemp.createTemp('sync_trigger_test_');
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

  test('a local write to a synced box notifies', () async {
    var notifications = 0;
    final subscription = await repository.watchLocalChanges(
      () => notifications++,
    );
    addTearDown(subscription.cancel);

    await Hive.box(BoxNames.libFav).put('song-1', {'videoId': 'song-1'});
    await pumpEventQueue();

    expect(notifications, greaterThan(0));
  });

  test('applying remote changes does not notify', () async {
    // Otherwise every pull would schedule a push of what was just received.
    var notifications = 0;
    final subscription = await repository.watchLocalChanges(
      () => notifications++,
    );
    addTearDown(subscription.cancel);

    await repository.applyRemote([_change('song-2')]);
    await pumpEventQueue();

    expect(Hive.box(BoxNames.libFav).containsKey('song-2'), isTrue);
    expect(notifications, 0);
  });

  test('a local write after a remote apply notifies again', () async {
    // The suppression must not leak past the apply that set it.
    var notifications = 0;
    final subscription = await repository.watchLocalChanges(
      () => notifications++,
    );
    addTearDown(subscription.cancel);

    await repository.applyRemote([_change('song-3')]);
    await pumpEventQueue();
    expect(notifications, 0);

    await Hive.box(BoxNames.libFav).put('song-4', {'videoId': 'song-4'});
    await pumpEventQueue();

    expect(notifications, greaterThan(0));
  });

  test('a saved album\'s song box is synced, not just the album entry', () async {
    // Regression: only playlists were enumerated, so saving an album synced its
    // LibraryAlbums entry while its contents never left the device — the album
    // appeared on the other device and opened empty.
    await Hive.box(BoxNames.libraryAlbums).put('MPREb_album', {
      'browseId': 'MPREb_album',
      'title': '2 Bunny 2 Deluxe',
    });
    await Hive.openBox('MPREb_album');

    var notifications = 0;
    final subscription = await repository.watchLocalChanges(
      () => notifications++,
    );
    addTearDown(subscription.cancel);

    await Hive.box('MPREb_album').add({'videoId': 'song-a', 'title': 'Track'});
    await pumpEventQueue();
    expect(
      notifications,
      greaterThan(0),
      reason: 'album songs must be watched',
    );

    final events = await repository.scan();
    final albumSongEvents = events.where(
      (event) => event.entityId.startsWith('MPREb_album:'),
    );
    expect(albumSongEvents, isNotEmpty, reason: 'album songs must be scanned');
    expect(albumSongEvents.first.entityType, 'playlistSongs');
  });

  test('remote album songs are applied, not rejected', () async {
    await Hive.box(BoxNames.libraryAlbums).put('MPREb_album', {
      'browseId': 'MPREb_album',
      'title': '2 Bunny 2 Deluxe',
    });

    await repository.applyRemote([
      {
        'entityId':
            'MPREb_album:${base64UrlEncode(utf8.encode(jsonEncode(0)))}',
        'operation': 'upsert',
        'payload': {'videoId': 'song-b', 'title': 'Track'},
      },
    ]);

    expect(Hive.box('MPREb_album').length, 1);
  });

  test('cancelling stops notifications', () async {
    var notifications = 0;
    final subscription = await repository.watchLocalChanges(
      () => notifications++,
    );
    await subscription.cancel();

    await Hive.box(BoxNames.libFav).put('song-5', {'videoId': 'song-5'});
    await pumpEventQueue();

    expect(notifications, 0);
  });
}

/// Mirrors the entity id the scan builds: `<box>:base64url(jsonEncode(key))`.
Map<String, dynamic> _change(String videoId) => {
  'entityId': 'LIBFAV:${base64UrlEncode(utf8.encode(jsonEncode(videoId)))}',
  'operation': 'upsert',
  'payload': {'videoId': videoId, 'title': 'Song'},
};

class _NoPlaylists implements PlaylistRepository {
  @override
  Future<List<Playlist>> getPlaylists() async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used here');
}
