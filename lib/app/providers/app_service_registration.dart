import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/app_platform_service.dart';
import '../../services/file_picker_service.dart';
import '../../utils/helper.dart';
import '../../utils/runtime_platform.dart';
import 'controller_providers.dart';
import 'service_providers.dart';

void registerAppServices(ProviderContainer container) {
  AppPlatformService.override = container.read(appPlatformContractProvider);
  newVersionCheckOverride = container.read(updateServiceContractProvider);
  FilePickerService.override = container.read(filePickerContractProvider);

  if (RuntimePlatform.isDesktop) {
    container.read(desktopSystemTrayProvider);
  }
  // The cloud playback receiver is deliberately NOT started here. It opens an
  // authenticated WebSocket, so starting it before sign-in would just retry-loop
  // against a 401. MyApp starts it once the account is authenticated.
}
