import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/models/media_Item_builder.dart';
import 'package:harmonymusic/services/metadata/song_metadata_service.dart';
import 'package:harmonymusic/services/resolver/resolver_client.dart';

import 'support/metadata_fakes.dart';

void main() {
  late FakeMusicService music;
  late FakeSongCache songCache;
  late FakeDownloads downloads;
  late FakeResolverClient resolver;
  late SongMetadataService service;

  SongMetadataService build({bool resolverEnabled = true}) =>
      SongMetadataService(
        music: music,
        songCache: songCache,
        downloads: downloads,
        resolverClient: resolver,
        settings: FakeSettings(resolverEnabled: resolverEnabled),
      );

  setUp(() {
    music = FakeMusicService();
    songCache = FakeSongCache();
    downloads = FakeDownloads();
    resolver = FakeResolverClient();
    service = build();
  });

  group('resolve', () {
    test('a cached song costs no network at all', () async {
      songCache.songs['aaaaaaaaaaa'] = MediaItem(
        id: 'aaaaaaaaaaa',
        title: 'Cached Song',
        artist: 'Cached Artist',
      );

      final item = await service.resolve('aaaaaaaaaaa');

      expect(item?.title, 'Cached Song');
      expect(music.resolveCalls, isEmpty);
      expect(resolver.batchCalls, isEmpty);
    });

    test('a downloaded song is used before any network call', () async {
      downloads.songs['bbbbbbbbbbb'] = {
        'videoId': 'bbbbbbbbbbb',
        'title': 'Offline Song',
        'artists': [
          {'name': 'Offline Artist'},
        ],
      };

      final item = await service.resolve('bbbbbbbbbbb');

      expect(item?.title, 'Offline Song');
      expect(music.resolveCalls, isEmpty);
      expect(resolver.batchCalls, isEmpty);
    });

    test('an empty-title cache entry is not trusted', () async {
      // A placeholder must never be mistaken for resolved metadata.
      songCache.songs['ccccccccccc'] = MediaItemBuilder.placeholder(
        'ccccccccccc',
      );
      music.metadata['ccccccccccc'] = MediaItem(
        id: 'ccccccccccc',
        title: 'Real Title',
      );

      final item = await service.resolve('ccccccccccc');

      expect(item?.title, 'Real Title');
    });

    test('the resolver answer wins when YouTube is slow', () async {
      resolver.tracks['ddddddddddd'] = {
        'videoId': 'ddddddddddd',
        'status': 'ready',
        'title': 'From Resolver',
        // The wire shape Resolver actually serializes (TrackMetadata.ToJson):
        // artists as {name} objects and seconds under `duration`. The C# record
        // spells those Artists/DurationSeconds, which is what this fixture used
        // to copy — so it asserted against a payload the server never sends.
        'artists': [
          {'name': 'Resolver Artist'},
        ],
        'duration': 213,
      };
      music.delay = const Duration(milliseconds: 300);
      music.metadata['ddddddddddd'] = MediaItem(
        id: 'ddddddddddd',
        title: 'From YouTube',
      );

      final item = await service.resolve('ddddddddddd');

      expect(item?.title, 'From Resolver');
      expect(item?.duration, const Duration(seconds: 213));
    });

    test(
      'a resolver miss falls back to YouTube without waiting for a timeout',
      () async {
        music.metadata['eeeeeeeeeee'] = MediaItem(
          id: 'eeeeeeeeeee',
          title: 'From YouTube',
        );

        final item = await service.resolve('eeeeeeeeeee');

        expect(item?.title, 'From YouTube');
      },
    );

    test('a resolver failure does not fail the resolution', () async {
      resolver.throwOnBatch = true;
      music.metadata['fffffffffff'] = MediaItem(
        id: 'fffffffffff',
        title: 'From YouTube',
      );

      final item = await service.resolve('fffffffffff');

      expect(item?.title, 'From YouTube');
    });

    test('returns null when neither source knows the song', () async {
      expect(await service.resolve('ggggggggggg'), isNull);
    });

    test('a resolved song is written back to the cache', () async {
      music.metadata['hhhhhhhhhhh'] = MediaItem(
        id: 'hhhhhhhhhhh',
        title: 'Fresh',
      );

      await service.resolve('hhhhhhhhhhh');
      await Future<void>.delayed(Duration.zero);

      expect(songCache.songs['hhhhhhhhhhh']?.title, 'Fresh');
    });

    test('concurrent requests for the same id resolve it once', () async {
      music.delay = const Duration(milliseconds: 50);
      music.metadata['iiiiiiiiiii'] = MediaItem(
        id: 'iiiiiiiiiii',
        title: 'Once',
      );

      final results = await Future.wait([
        service.resolve('iiiiiiiiiii'),
        service.resolve('iiiiiiiiiii'),
        service.resolve('iiiiiiiiiii'),
      ]);

      expect(results.map((item) => item?.title), everyElement('Once'));
      expect(music.resolveCalls, ['iiiiiiiiiii']);
    });

    test('the resolver is skipped entirely when disabled', () async {
      service = build(resolverEnabled: false);
      resolver.tracks['jjjjjjjjjjj'] = {
        'videoId': 'jjjjjjjjjjj',
        'status': 'ready',
        'title': 'From Resolver',
      };
      music.metadata['jjjjjjjjjjj'] = MediaItem(
        id: 'jjjjjjjjjjj',
        title: 'From YouTube',
      );

      final item = await service.resolve('jjjjjjjjjjj');

      expect(item?.title, 'From YouTube');
      expect(resolver.batchCalls, isEmpty);
    });
  });

  group('resolveBatch', () {
    test('asks the resolver once for the whole chunk', () async {
      for (final id in ['aaaaaaaaaaa', 'bbbbbbbbbbb', 'ccccccccccc']) {
        resolver.tracks[id] = {
          'videoId': id,
          'status': 'ready',
          'title': 'Song $id',
        };
      }

      final items = await service.resolveBatch([
        'aaaaaaaaaaa',
        'bbbbbbbbbbb',
        'ccccccccccc',
      ]);

      expect(items.length, 3);
      expect(resolver.batchCalls.length, 1);
    });

    test('splits a long queue into server-sized chunks', () async {
      final ids = List.generate(
        250,
        (index) => index.toString().padLeft(11, '0'),
      );

      await service.resolveBatch(ids);

      expect(resolver.batchCalls.length, 3);
      expect(
        resolver.batchCalls.every(
          (chunk) => chunk.length <= ResolverClient.metadataBatchLimit,
        ),
        isTrue,
      );
    });

    test('cached ids are never sent to the resolver', () async {
      songCache.songs['aaaaaaaaaaa'] = MediaItem(
        id: 'aaaaaaaaaaa',
        title: 'Cached',
      );
      resolver.tracks['bbbbbbbbbbb'] = {
        'videoId': 'bbbbbbbbbbb',
        'status': 'ready',
        'title': 'Remote',
      };

      final items = await service.resolveBatch(['aaaaaaaaaaa', 'bbbbbbbbbbb']);

      expect(items.length, 2);
      expect(resolver.batchCalls.single, ['bbbbbbbbbbb']);
    });

    test('ids the resolver cannot answer fall through to YouTube', () async {
      resolver.tracks['aaaaaaaaaaa'] = {
        'videoId': 'aaaaaaaaaaa',
        'status': 'ready',
        'title': 'Remote',
      };
      music.metadata['bbbbbbbbbbb'] = MediaItem(
        id: 'bbbbbbbbbbb',
        title: 'YouTube',
      );

      final items = await service.resolveBatch(['aaaaaaaaaaa', 'bbbbbbbbbbb']);

      expect(items['aaaaaaaaaaa']?.title, 'Remote');
      expect(items['bbbbbbbbbbb']?.title, 'YouTube');
    });

    test('unresolvable ids are simply absent, not null entries', () async {
      music.metadata['aaaaaaaaaaa'] = MediaItem(
        id: 'aaaaaaaaaaa',
        title: 'Known',
      );

      final items = await service.resolveBatch(['aaaaaaaaaaa', 'zzzzzzzzzzz']);

      expect(items.keys, ['aaaaaaaaaaa']);
    });
  });
}
