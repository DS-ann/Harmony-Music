# Auth0 “Use another account” plan

## Goal

Let a signed-out Harmony Music user request a genuinely fresh Auth0/Google
authentication flow from the app, without clearing browser cookies or accepting
the wrong account on Auth0’s consent page.

## Implementation

1. Keep the existing Login / Register action as the normal authentication path.
2. Add a localized Use another account action to the signed-out Account section.
3. Extend the authentication service boundary so that action can request account
   selection explicitly.
4. For account selection, send `prompt=login` to Auth0 so its existing SSO
   session cannot silently choose the previous Auth0 user. Configure the Google
   connection itself with a static upstream `prompt=select_account` value so
   Google opens its real account chooser whenever Auth0 reauthenticates there.
5. Keep the existing library merge/replace and cross-account cleanup behavior
   identical for either login entry point.
6. Add focused service and integration coverage proving normal login and
   account-selection login use distinct requests.

## Required Auth0 tenant configuration

Configure the Google social connection’s `options.upstream_params.prompt` with
the static value `select_account`. Auth0’s supported dynamic aliases map an
upstream parameter to a fixed set of Auth0 authorization parameters and cannot
map a custom `ext-*` parameter as originally considered.

Harmony Music should use a first-party Native application in Auth0. If the
current Auth0 application was created as third-party, create a replacement
first-party Native application because Auth0 application ownership is
immutable.

## Verification

- Regenerate Flutter localizations.
- Format changed Dart files.
- Run focused Auth0/account-switch tests.
- Run `flutter analyze` and report any unrelated existing failures separately.
