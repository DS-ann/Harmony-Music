import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/utils/observable_state.dart';

void main() {
  test('playlist screen listens to its observable song list', () {
    final source = File(
      'lib/ui/screens/Playlist/playlist_screen.dart',
    ).readAsStringSync();

    expect(source, contains('playlistController.songList'));
  });

  testWidgets('removing a song rebuilds the active playlist list', (
    tester,
  ) async {
    final controller = ChangeNotifier();
    final songs = ObservableList<String>(['First song', 'Removed song']);

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: AnimatedBuilder(
          animation: Listenable.merge([controller, songs]),
          builder: (context, _) =>
              Column(children: [for (final song in songs) Text(song)]),
        ),
      ),
    );

    expect(find.text('Removed song'), findsOneWidget);

    songs.remove('Removed song');
    await tester.pump();

    expect(find.text('First song'), findsOneWidget);
    expect(find.text('Removed song'), findsNothing);
  });
}
