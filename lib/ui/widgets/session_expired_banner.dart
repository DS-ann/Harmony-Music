import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:harmonymusic/l10n/l10n.dart';

import '../../app/providers/auth_providers.dart';
import '../../app/providers/controller_providers.dart';

/// Tells the user their session lapsed and sync has stalled.
///
/// Nothing used to say so: `tryRestoreSession` returned null, the library
/// quietly stopped reaching the account, and edits piled up in the outbox with
/// no sign anything was wrong. Dismissible, because it should not block the
/// app — the settings badge is what persists until it is actually resolved.
///
/// Tapping it goes where the problem can actually be fixed: the Settings
/// Account section, expanded, with the sign-in button in view. Telling someone
/// they are signed out and leaving them to find the way back is half a fix.
class SessionExpiredBanner extends ConsumerWidget {
  const SessionExpiredBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authController = ref.watch(authControllerProvider);
    if (!authController.showSessionExpiredBanner) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: 5, bottom: 8),
      child: Material(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () {
            ref.read(settingsScreenControllerProvider)
                .requestAccountSectionReveal();
            ref.read(homeScreenControllerProvider).openSettingsTab();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Icon(
                  Icons.cloud_off_outlined,
                  size: 20,
                  color: theme.colorScheme.onErrorContainer,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    context.l10n.sessionExpiredMessage,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onErrorContainer,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  color: theme.colorScheme.onErrorContainer,
                  splashRadius: 18,
                  visualDensity: const VisualDensity(
                    horizontal: -3,
                    vertical: -3,
                  ),
                  tooltip: context.l10n.dismiss,
                  onPressed: authController.dismissSessionExpiredNotice,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
