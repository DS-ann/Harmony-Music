# Separate Windows development and release environments

## Summary

Give Windows Debug builds a distinct application identity while preserving the existing installed
Release identity. Debug and Release must use separate local databases, downloaded files, secure
credentials, Auth0 callback handlers, and single-instance coordination so they can run
simultaneously.

## Implementation

- Use `harmonymusic_dev` as the Debug `ProductName` in the Windows version resource while keeping
  `harmonymusic` for non-Debug builds. `path_provider_windows` and
  `flutter_secure_storage_windows` derive their directories from `CompanyName\ProductName`, so this
  separates Debug under `%APPDATA%\com.anandnet\harmonymusic_dev`.
- Give the Debug runner its own window title, mutex, named pipe, callback prefix, and protocol
  registry key. Keep all existing Release values unchanged.
- Use `harmonymusic-dev://callback` for Windows Debug Auth0 and retain
  `harmonymusic://callback` for Profile/Release.
- Update the local Windows protocol-registration helper to register the Debug scheme and executable.
- Leave the Release installer identity and installation directory unchanged; Debug continues to run
  from Flutter's build output rather than installing over Release.

## Interfaces and Configuration

- Add `harmonymusic-dev://callback` to the Auth0 application's allowed callback and logout URLs.
- No data migration: existing `%APPDATA%\com.anandnet\harmonymusic` remains Release data; Debug
  starts with an independent local environment.
- Signing into the same cloud account can still synchronize safe cloud data between environments.

## Verification

- Add regression checks for distinct Debug native identifiers and matching Dart/native callback
  schemes.
- Run focused tests and Dart analysis.
- Build Windows Debug and confirm its executable metadata reports `harmonymusic_dev`.
- Confirm Debug and installed Release can run simultaneously and create different application
  support directories.
