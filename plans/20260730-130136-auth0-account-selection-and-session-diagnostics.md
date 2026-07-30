# Auth0 account selection and session diagnostics

## Goal

Make interactive authentication let the user choose the intended account in
both development and release installations, while keeping each installation's
local session independent and making unexpected session-restoration failures
diagnosable without exposing credentials.

## Plan

1. Pass the OIDC `prompt=select_account` parameter to every interactive Auth0
   login on Android/iOS/macOS and Windows so a shared browser SSO session does
   not silently choose the previously used account.
2. Keep ordinary logout scoped to Harmony Music and do not enable federated
   logout, which could sign the user out of Google and unrelated browser apps.
3. Preserve the existing separate platform credential stores and add safe
   debug diagnostics when restoring credentials fails. Diagnostics may report
   the exception type but must never print access tokens, refresh tokens, user
   profiles, or other credential contents.
4. Add focused tests that verify both interactive login paths request account
   selection and that restoration diagnostics remain credential-safe.
5. Format changed Dart files, run the focused authentication tests, and run
   targeted static analysis.
