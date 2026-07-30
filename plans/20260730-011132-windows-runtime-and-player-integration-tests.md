# Windows runtime packaging and player integration tests

## Goals

- Make the Windows release installer include the native vcpkg runtime DLLs
  required by `auth0_flutter`, including `cpprest_2_10.dll`.
- Prevent GitHub Actions from publishing another Windows installer when the
  required runtime DLLs are absent.
- Add deterministic integration coverage for the app's core player behavior
  using the existing real-app test harness and fake external boundaries.

## Implementation

1. Enable vcpkg app-local dependency installation before CMake's first
   `project()` call so transitive native runtime DLLs are copied into Flutter's
   Windows release directory.
2. Add a Windows release-workflow assertion for the Auth0 native runtime DLLs
   before signing and Inno Setup packaging.
3. Extend the integration-test audio fake so it models and records playback,
   seeking, queue navigation, shuffle, repeat, and queue mutation.
4. Expose the shared audio fake through the test-app handle.
5. Add player integration scenarios covering song selection, mini/full player
   presentation, play/pause, next/previous, seeking, shuffle/repeat, favorites,
   queue selection/removal, and queue-loop/clear controls.
6. Include the player suite in `integration_test/all_tests.dart`.

## Verification

- Format changed Dart files.
- Run static analysis.
- Run the focused player integration suite on an available Flutter device.
- Run relevant existing unit tests and validate workflow/YAML plus Git diff
  whitespace.
