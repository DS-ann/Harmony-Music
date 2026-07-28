# Stop the player flashing shimmer on seek and replay

## Context

Scrubbing the progress bar on an offline/cached song — or hitting the previous button to
restart the current track — briefly collapses the title and artist into grey
`BasicShimmerContainer` bars and swaps the play icon for a spinner. Nothing is actually
unknown in those moments: the song is fully resolved and the audio is local. The flash is
pure noise.

Root cause, in `lib/ui/player/player_controller.dart:132-135`:

```dart
bool get isCurrentSongLoading =>
    buttonState.value == PlayButtonState.loading ||
    (currentSong.value != null && MediaItemBuilder.isResolving(currentSong.value!));
```

`buttonState` becomes `loading` on `AudioProcessingState.buffering`
(`_listenForChangesInPlayerState`, :1021-1022, no debounce). Both just_audio and media_kit
emit a transient buffering event on *every* seek, including seeks to zero and seeks into a
local file. So an audio-engine implementation detail decides whether we render a title we
already have.

Two separate mistakes are folded together:

1. **The metadata shimmer is asking the wrong question.** "Do we know what this song is?" is
   a property of the `MediaItem`, not of the audio pipeline.
2. **The play-button spinner has no grace period.** A 40 ms rebuffer should not produce a
   visible spinner.

Outcome: seek, previous-button restart, and brief rebuffers produce no visual change at all.
Genuine unknowns (cloud handoff placeholders) and genuine stalls still get feedback.

While tracing this I found a latent bug on the same code path, which the user asked to
include — see step 4.

## Verified facts this plan relies on

- `isCurrentSongLoading` has exactly two consumers: `mini_player.dart:169,195` and
  `player_control.dart:58`. Both only render under `hasDisplayableCurrentSong`, and
  `isDisplayableSong` (:124-128) already guarantees *non-empty title OR isResolving*.
- Every "we genuinely don't know this song" producer installs a `MediaItemBuilder.placeholder`
  item, so `MediaItemBuilder.isResolving` alone covers all of them:
  `prepareIncomingCloudSong` (:633-647), `beginRemoteSongTransition` (:137-182), the mirrored
  queue (`cloud_playback_receiver.dart:250,545,650`). `copyWith` preserves `extras`.
  Resolution clears the flag explicitly (`_applyRemoteSongMetadata`, :489-498).
- `_currentSongResolving` must **not** be in the predicate: `applyRemoteProgress:399` assigns
  it from the peer's `progress['loading']`, which is itself derived from the *target's*
  `AudioProcessingState.buffering`. Including it reintroduces the exact same bug one device
  removed.

## Changes

### 1. Redefine the metadata predicate — `lib/ui/player/player_controller.dart:132-135`

```dart
/// True only when we do not yet know *what* this song is.
///
/// Deliberately independent of [buttonState]: a seek or a previous-button
/// restart on an already-resolved (often cached) song makes the audio engine
/// emit a transient buffering event, and folding that in collapsed a title we
/// already had into shimmer bars. Audio being busy is the play button's
/// business, not the title's.
bool get isCurrentSongLoading {
  final song = currentSong.value;
  if (song == null) return false;
  return MediaItemBuilder.isResolving(song) || song.title.trim().isEmpty;
}
```

Rewrite the now-stale comments at `player_control.dart:59-61` and `mini_player.dart:165-167`
to describe "id-only, metadata unresolved" rather than "loading".

**Accepted behaviour change (user-confirmed):** on a local song change, `currentSong` updates
only when the handler emits the new `mediaItem` (:1247), while `isSongLoading = true` fires
earlier (`audio_handler.dart:1812`). That gap now holds the *previous* title instead of
shimmering, then swaps. Strictly less flashing; the play-button spinner still signals the
change.

### 2. Grace period before the buffering spinner — `player_controller.dart:998-1046`

Replace the mapping at lines 1018-1033:

```dart
final immediateLoading =
    _currentSongResolving ||
    processingState == AudioProcessingState.loading ||
    (_isWaitingForCurrentSourceStart &&
        processingState != AudioProcessingState.completed &&
        processingState != AudioProcessingState.error);
if (immediateLoading) {
  _cancelBufferingGrace();
  _setButtonState(PlayButtonState.loading);
} else if (processingState == AudioProcessingState.buffering) {
  _armBufferingGrace(isPlaying);
} else {
  _cancelBufferingGrace();
  if (!isPlaying ||
      processingState == AudioProcessingState.error ||
      processingState == AudioProcessingState.completed) {
    _setButtonState(PlayButtonState.paused);
  } else {
    _setButtonState(PlayButtonState.playing);
  }
}
```

New members next to `_setButtonState` (:1080):

```dart
/// A seek or a restart on a cached song makes the engine dip into buffering
/// for a few dozen milliseconds. Swapping the play icon for a spinner that
/// fast reads as a glitch, so only a rebuffer that outlasts this window is
/// worth telling the user about. Genuine loads bypass it.
static const _bufferingSpinnerGrace = Duration(milliseconds: 350);
Timer? _bufferingGraceTimer;

void _armBufferingGrace(bool isPlaying) {
  if (buttonState.value == PlayButtonState.loading) return;
  _setButtonState(isPlaying ? PlayButtonState.playing : PlayButtonState.paused);
  if (_bufferingGraceTimer != null) return; // one shot per buffering episode
  _bufferingGraceTimer = Timer(_bufferingSpinnerGrace, () {
    _bufferingGraceTimer = null;
    if (_disposed || _cloudRemoteStateActive) return;
    if (_audioHandler.playbackState.value.processingState ==
        AudioProcessingState.buffering) {
      _setButtonState(PlayButtonState.loading);
    }
  });
}

void _cancelBufferingGrace() {
  _bufferingGraceTimer?.cancel();
  _bufferingGraceTimer = null;
}
```

Order matters in `_armBufferingGrace`: set the button *before* arming, and never cancel from
inside `_setButtonState`, or the arm kills its own timer. `_disposed` already exists (:2441);
add `_cancelBufferingGrace();` to `dispose()` beside `sleepTimer?.cancel()` (:2452).

Keep the literals `_isWaitingForCurrentSourceStart`, `_isReadySourceStart(playerState)`,
`processingState != AudioProcessingState.ready` and `_setButtonState(PlayButtonState.loading)`
inside `_listenForChangesInPlayerState` — `test/player_controller_queue_order_test.dart:197-229`
asserts on them. The shape above keeps all four.

### 3. Same rule on the handoff tail — `player_controller.dart:610-620`

`setCurrentSongResolving`'s else-branch maps `buffering → loading` immediately, and runs at
the end of every handoff (`cloud_playback_receiver.dart:709`). Route the buffering case
through `_armBufferingGrace(playbackState.playing)` instead; keep loading/playing/paused as-is.

### 4. Fix the seek-before-start wedge — `player_controller.dart:1935-1939`

`_pendingPlaybackStartPosition` is written only by `_beginPendingSourceStart` (:1332-1338) and
`_clearPendingSourceStart` (:1341-1346). Neither `seek()` nor `MyAudioHandler.seek` retargets
it. So: tap a song, scrub to 2:00 before its first `ready + playing` event lands →
`_isSourceStartPosition` (:1311-1314) can never be satisfied, `_isReadyPausedPendingSource`
can't rescue it (requires `!playing`), and for the rest of the track the button is pinned on
loading (:1023-1026) *and* the progress bar is frozen (the position and buffered listeners at
:1143-1219 early-return). Same class of bug as the one documented at :1302-1310, which fixed
only the cloud-resume case.

```dart
Future<void> seek(Duration position) async {
  if (_routeToHost(SessionCommand.seek(position))) return;
  if (_cloudRemoteStateActive) _applyOptimisticRemoteSeek(position);
  // A seek issued before the new source reported its first ready frame moves
  // the goalposts: the start is now measured from where the user dropped the
  // thumb, not from zero. Without this the pending start never clears, which
  // pins the play button on loading and freezes the progress bar for the rest
  // of the track.
  _retargetPendingSourceStart(position);
  await _playbackCommands.seek(position);
}

void _retargetPendingSourceStart(Duration position) {
  if (!_isWaitingForCurrentSourceStart) return;
  _pendingPlaybackStartPosition = position;
  _expectedSourceStartPosition = position;
}
```

Call it from `prev()`'s restart branches too (:1905, :1908 region) for the same reason.

### Explicitly out of scope

The local seek snap-back (thumb reverting for 1-2 frames on drag end, because
`AudioService.position` extrapolates from a stale `updatePosition`) — the user chose to leave
it. The remote path's `_applyOptimisticRemoteSeek` (:527-533) + stale-sample window
(:340-355) is the idiom to mirror if it's picked up later.

## Tests

The suite is source-text assertion based (`_methodBlock` helpers) — there is no behavioural
`PlayerController` harness anywhere in `test/`. Match that style. Nothing currently breaks:
`cloud_song_loading_feedback_test.dart:504-511` still passes (both surfaces keep calling
`isCurrentSongLoading`, shimmer count unchanged); `player_controller_queue_order_test.dart`
passes given the literals above; the cloud role-safety/session-v2 tests assert the *publisher*
side (target's buffering → `loading` in the progress frame), which stays as-is — a remote
controller still wants to know its target is rebuffering, only the consumer's interpretation
changes.

Add to `test/cloud_song_loading_feedback_test.dart` (its `setUpAll` already loads the sources):

```dart
test('a resolved song never shimmers because audio is busy', () {
  final getter = player.substring(
    player.indexOf('bool get isCurrentSongLoading'),
    player.indexOf('int? beginRemoteSongTransition'),
  );
  expect(getter, contains('MediaItemBuilder.isResolving'));
  expect(getter, isNot(contains('buttonState')));
  expect(getter, isNot(contains('_currentSongResolving')));
});

test('a brief rebuffer does not swap the play icon for a spinner', () {
  final block = _methodBlock(player, '_listenForChangesInPlayerState');
  final arm = _methodBlock(player, '_armBufferingGrace');
  expect(player, contains('static const _bufferingSpinnerGrace'));
  expect(block, contains('_armBufferingGrace('));
  expect(block, contains('_cancelBufferingGrace();'));
  expect(
    block.indexOf('final immediateLoading'),
    lessThan(block.indexOf('_armBufferingGrace(')),
  );
  expect(arm, contains('AudioProcessingState.buffering'));
  expect(_methodBlock(player, 'dispose'), contains('_cancelBufferingGrace()'));
});

test('seeking before a source starts retargets the pending start', () {
  final seek = _methodBlock(player, 'seek');
  expect(seek, contains('_retargetPendingSourceStart(position)'));
  final retarget = _methodBlock(player, '_retargetPendingSourceStart');
  expect(retarget, contains('_pendingPlaybackStartPosition = position'));
  expect(retarget, contains('_expectedSourceStartPosition = position'));
});
```

`isCurrentSongLoading` is an expression-bodied getter, hence the substring slice rather than
`_methodBlock`.

## Verification

1. `flutter analyze --no-pub` and `flutter test` via the `harmony-flutter-dart` MCP server
   (`timeout_ms: 600000`).
2. Manual, on the user's device (I do not run the app):
   - Play a **downloaded/cached** song. Scrub 0:01 → 0:05 → title, artist, and play icon must
     not change at all.
   - Press previous within 5 s to restart the same song → no shimmer, no spinner.
   - Play a **network** song, scrub far ahead into unbuffered audio → spinner appears only
     after ~350 ms of real buffering; title/artist never shimmer.
   - Tap a different song in the queue → title swaps old → new with no shimmer between;
     spinner shows while it loads.
   - Tap a song and immediately scrub to mid-track → progress bar keeps ticking and the play
     button settles (the step-4 wedge fix).
   - Cloud handoff / listen-together: an id-only incoming song still shimmers until its
     metadata resolves.
3. `printINFO` `surface[...]` lines (`_logSurface`, :1092-1110) in the log confirm
   `loading=false` throughout a cached-song seek.

Before implementing, save this plan to the repo-root `plans/` directory as a timestamped
Markdown file, per `CLAUDE.md`.
