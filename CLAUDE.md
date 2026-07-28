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

**Narrow exception: `flutter test integration_test/...` on a dedicated, disposable AVD.**
Jan granted this on 2026-07-28 specifically so `integration_test/` suites can be verified
end-to-end instead of only analyzer-checked, after a `flutter test -d windows` run surfaced
that Windows integration runs launch the real installed build with real account data — a
device that must never be touched this way.

This exception covers only an Android Virtual Device created solely for this purpose (e.g.
named with a `claude-` prefix), never installed with a real account, never reused as a manual
testing device, and deleted (`avdmanager delete avd`) once the run is done. In scope, on that
AVD only: `avdmanager create avd`, launching the emulator, `flutter test integration_test/...`,
`adb uninstall`/wiping that same AVD, and `avdmanager delete avd` to tear it down.

Still completely out of scope, no exception: the user's own AVDs (e.g. `Medium_Phone`), any
physical device, the Windows build, and `flutter run`/`attach`/`install`/`drive` anywhere. If
an integration run needs the user's real device or the Windows app, that's still theirs to do.
