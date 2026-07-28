# Windows Auth0 setup

Harmony uses the fixed Windows callback URL `harmonymusic://callback`.

In the Auth0 Dashboard, open the Native application used by Harmony and add
that exact value to both **Allowed Callback URLs** and **Allowed Logout URLs**.
Save the application settings before trying to log in again.

The Windows installer registers the `harmonymusic` protocol for the current
user. For a local Flutter build, first build the app and then run:

```powershell
.\windows\register_auth0_protocol.ps1
```

To register a Release build instead, pass its executable path with
`-ExecutablePath`.
