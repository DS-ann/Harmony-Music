/// Shuffle/repeat options carried by an account playback session.
///
/// Fields are nullable for wire compatibility: an older client may omit them,
/// in which case the receiving device must keep its current value instead of
/// interpreting the omission as `false`.
class CloudPlaybackModes {
  const CloudPlaybackModes({this.shuffle, this.repeat, this.queueLoop});

  final bool? shuffle;
  final bool? repeat;
  final bool? queueLoop;

  bool get hasAny => shuffle != null || repeat != null || queueLoop != null;

  factory CloudPlaybackModes.fromMap(Map<String, dynamic> value) {
    return CloudPlaybackModes(
      shuffle: value['shuffle'] is bool ? value['shuffle'] as bool : null,
      repeat: value['repeat'] is bool ? value['repeat'] as bool : null,
      queueLoop: value['queueLoop'] is bool ? value['queueLoop'] as bool : null,
    );
  }

  CloudPlaybackModes merge(CloudPlaybackModes newer) {
    return CloudPlaybackModes(
      shuffle: newer.shuffle ?? shuffle,
      repeat: newer.repeat ?? repeat,
      queueLoop: newer.queueLoop ?? queueLoop,
    );
  }

  Map<String, Object?> toMap() => {
    if (shuffle != null) 'shuffle': shuffle,
    if (repeat != null) 'repeat': repeat,
    if (queueLoop != null) 'queueLoop': queueLoop,
  };

  @override
  bool operator ==(Object other) {
    return other is CloudPlaybackModes &&
        other.shuffle == shuffle &&
        other.repeat == repeat &&
        other.queueLoop == queueLoop;
  }

  @override
  int get hashCode => Object.hash(shuffle, repeat, queueLoop);
}
