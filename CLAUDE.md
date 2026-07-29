# CLAUDE.md

## Accepted Plans

Before implementing an explicitly accepted plan, save its full accepted content as a timestamped Markdown file in the repository-root `plans/` directory.

## Flutter/Dart MCP server

This repo ships a small dependency-free MCP stdio server at `mcp/flutter_dart_server.js`
that exposes the repo-local Flutter SDK (`.flutter/`) as two tools:

- `flutter` — runs `.flutter/bin/flutter(.bat) <args>` in the repo (or a workspace-relative
  `working_directory`)
- `dart` — runs `.flutter/bin/dart(.bat) <args>` the same way

It's registered as a project MCP server in `.mcp.json` (server name `harmony-flutter-dart`).
After `.mcp.json` changes, the session needs to be restarted/reloaded (and the new project
server approved) before these tools are actually callable.

**Prefer these tools over raw Bash calls to `.flutter\bin\flutter.bat` / `dart.bat`** once
connected — e.g. `flutter({args: ["analyze", "--no-pub"]})`, `flutter({args: ["test"]})`,
`dart({args: ["format", "lib/..."]})`.

**Always pass `timeout_ms: 600000`** (the tool's own cap). The default (120000) is too short
for this repo — `flutter analyze` and `flutter test` here routinely run several minutes,
sometimes longer on a cold analyzer-server start. A timed-out call still returns whatever
stdout was captured (check it before assuming failure), but the exit code is lost, so just
budget the full 600s up front instead of retrying.

**Do not run `flutter analyze` routinely.** It costs minutes per call here and is almost
always redundant: `flutter test` and `flutter test integration_test/all_tests.dart` compile
the same code and surface real breakage, and the IDE/LSP already reports analyzer diagnostics
as files are edited. Do not run it after each individual edit, and do not run it as a
"verification" step when a test run is already planned. Reach for it only when specifically
asked, or when chasing something tests genuinely cannot see (an unused import or a
lint-only rule in code no test compiles). Prefer narrowing it to a path
(`analyze --no-pub lib/foo.dart`) over analyzing the whole repo.

**Still bound by the standing rule: never run, launch, install, attach to, or otherwise
control the app on a device or emulator.** This server is a raw passthrough with no
subcommand allowlist — it will execute `flutter run` / `flutter attach` / `flutter install` /
`flutter drive` if asked. Do not pass those subcommands through it. Only `analyze`, `test`,
`format`, `fix`, `pub`, and similarly inert subcommands are in scope. The user builds, runs,
and tests the app themselves on their own devices.

**Reading logs is allowed, and is the preferred way to diagnose runtime behaviour.**
Observing a session the user is already running is not controlling it. In scope:

- `adb devices`, `adb logcat` (including `-c` to clear, `-d` to dump, `-s`/`--pid` to filter)
- `adb shell` commands that only *read* state (`dumpsys`, `getprop`, `pm list packages`)
- reading the Windows build's console/log output, and any file under the app's log directory

Out of scope regardless: `adb install`/`uninstall`, `adb shell am start`/`am force-stop`,
`adb reboot`, `adb push`/`pull` into app storage, `adb shell pm clear`, and anything else that
starts, stops, installs, or mutates the app or the device. If a log needs the app relaunched
or a step reproduced, ask the user to do it and say exactly what to do.

**Narrow exception: `flutter test integration_test/...` on the dedicated `claude_integration_test` AVD.**
Jan granted this on 2026-07-28 specifically so `integration_test/` suites can be verified
end-to-end instead of only analyzer-checked, after a `flutter test -d windows` run surfaced
that Windows integration runs launch the real installed build with real account data — a
device that must never be touched this way.

The AVD `claude_integration_test` already exists and is kept between sessions (Jan asked for
it to stay, 2026-07-29) — reuse it rather than creating a new one, and do not delete it. It is
for automated runs only: never sign a real account into it, never use it as a manual testing
device. In scope, on that AVD only: launching the emulator, `flutter test integration_test/...`,
and `adb uninstall`/wiping that same AVD. Recreate it with `avdmanager create avd` only if it
is missing.

If it starts behaving strangely — tests timing out, a file that ran in 30s taking minutes,
assertions failing that passed earlier — restart the emulator before hunting for a code
regression. A long-lived instance degrades, and that has already cost a debugging detour once.

Still completely out of scope, no exception: the user's own AVDs (e.g. `Medium_Phone`), any
physical device, the Windows build, and `flutter run`/`attach`/`install`/`drive` anywhere. If
an integration run needs the user's real device or the Windows app, that's still theirs to do.
