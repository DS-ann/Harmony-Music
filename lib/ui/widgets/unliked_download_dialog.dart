import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:harmonymusic/l10n/l10n.dart';

import '../../domain/repositories/library_repository.dart';
import '../../domain/repositories/settings_repository.dart';

/// What the user chose when told a download will not show in Songs.
enum UnlikedDownloadChoice { likeAndDownload, downloadOnly, cancel }

/// Explains, once, that Songs lists downloads that are in the account's
/// library — so downloading something unliked will appear to do nothing.
///
/// Only the explicit download button needs this. The auto-download paths fire
/// *because* a song was just liked, so they are already consistent and must
/// stay silent rather than putting a modal in front of a background action.
///
/// Returns null when there is nothing to explain: no account to scope to, the
/// song is already liked, or the user has dismissed the notice for good.
Future<UnlikedDownloadChoice?> maybeAskAboutUnlikedDownload({
  required BuildContext context,
  required MediaItem song,
  required SettingsRepository settings,
  required LibraryRepository library,
}) async {
  if (settings.getCloudAccountSubject() == null) return null;
  if (settings.getUnlikedDownloadNoticeDismissed()) return null;
  if (await library.isFavorite(song.id)) return null;
  if (!context.mounted) return null;

  var dismiss = false;
  final choice = await showDialog<UnlikedDownloadChoice>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(dialogContext.l10n.downloadNotInLibraryTitle),
      content: StatefulBuilder(
        builder: (context, setInnerState) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(dialogContext.l10n.downloadNotInLibraryMessage),
            const SizedBox(height: 8),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              value: dismiss,
              title: Text(dialogContext.l10n.dontAskAgain),
              onChanged: (value) =>
                  setInnerState(() => dismiss = value ?? false),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () =>
              Navigator.pop(dialogContext, UnlikedDownloadChoice.downloadOnly),
          child: Text(dialogContext.l10n.downloadOnly),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            dialogContext,
            UnlikedDownloadChoice.likeAndDownload,
          ),
          child: Text(dialogContext.l10n.likeAndDownload),
        ),
      ],
    ),
  );

  // Remembered whichever way they answered — the point is that they now know.
  // Dismissing the dialog outright leaves it enabled, since nothing was read.
  if (dismiss && choice != null) {
    await settings.setUnlikedDownloadNoticeDismissed(true);
  }
  if (choice == UnlikedDownloadChoice.likeAndDownload) {
    await library.setFavorite(song, true);
  }
  return choice ?? UnlikedDownloadChoice.cancel;
}
