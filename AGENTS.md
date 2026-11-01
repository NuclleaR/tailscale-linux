# AGENTS.md

Guidance for coding agents working in this repository. For what the app is
and how to build it, see [README.md](README.md).

## Decisions already made

Do not revisit these without the maintainer asking:

- **Talk to `tailscaled` through the LocalAPI** over its unix socket, not by
  running the `tailscale` CLI.
- **Tray: `tray_manager` 0.8 native API** (`package:tray_manager/tray_manager.dart`,
  built on nativeapi). Do not use `package:tray_manager/legacy.dart`; it is
  deprecated.
- **Window: `window_manager` 0.6** is used only to show and focus the window.
  Starting hidden and hiding on close are done in C in
  `linux/runner/my_application.cc`.
- **State: plain `ChangeNotifier`**. No state-management packages.
- **Linux only** (`--platforms=linux`).
- **No new dependencies** without the maintainer's approval. This includes
  dev dependencies and code generators.

## Commands

```sh
flutter analyze
flutter test
dart format lib test
flutter build linux --debug
build/linux/x64/debug/bundle/tailscale_linux    # run the built app
```

Before reporting a change as done, run `flutter analyze` and `flutter test`,
and format the code with `dart format`.

## Architecture

- `lib/tailscale/local_api.dart`: `LocalApiClient`, HTTP over the unix socket.
  Throws `LocalApiException` on any non-2xx response.
- `lib/tailscale/status.dart`: models parsed from LocalAPI JSON. Parsing is
  lenient: a missing field gets a default and never throws.
- `lib/tailscale/tailscale_controller.dart`: the single source of app state.
  Subscribes to the IPN bus, re-reads status and profiles on every event, and
  reconnects after the bus drops.
- `lib/tray/tray_menu.dart`: `buildTrayMenu` is a **pure function** from state
  to a `TrayEntry` tree. Menu logic belongs here, not in the presenter.
- `lib/tray/tray_presenter.dart`: renders `TrayEntry` trees to native menus.
  Rebuilds the whole menu on every state change.
- `lib/main.dart`: wiring, and dispatch of `TrayCommand`s. A `403` from an
  action re-runs the access check and shows the window.

## LocalAPI notes

- Requests must use the `Host` header `local-tailscaled.sock`. tailscaled
  rejects other hosts. `LocalApiClient` does this already.
- Write access: root or the user set with `tailscale set --operator`.
  Otherwise write endpoints answer `403`. The access check posts the current
  prefs to `check-prefs`, which validates them without changing anything.
- Prefs edits are `MaskedPrefs`: every changed field `X` needs `XSet: true`.
- `watch-ipn-bus?mask=18` = `NotifyInitialState | NotifyNoPrivateKeys`.
  `NotifyRateLimit` (256) is no longer supported: the request fails with it.
- Peer `ID` in `status` is the stable node ID that `ExitNodeID` expects.
- To see real responses:
  `curl --unix-socket /var/run/tailscale/tailscaled.sock http://local-tailscaled.sock/localapi/v0/status`.
  Only use read endpoints this way: write endpoints change the maintainer's
  real Tailscale setup.

## nativeapi gotchas

- Dart wrappers (`TrayIcon`, `Menu`, `MenuItem`, `Image`) free their native
  handle when garbage collected. Keep a reference for as long as the object
  must exist; `_NativeMenu` holds every one.
- On Linux the panel opens the menu itself. The menu is only exported after
  `setContextMenuTrigger(...)` has been called. Tray icon click events are not
  delivered on Linux.
- Dispose a replaced menu later (`Timer.run`), because its item's click
  callback may be the code that is running at that moment.
- Some platforms tick a checkbox item on click by themselves. The presenter
  resets the state, and the menu changes only when the real state changes.

## Tests

- `test/tray_menu_test.dart` asserts on the menu through `describe()`, a
  readable list of strings. Add a case there for any menu change.
- `test/local_api_test.dart` runs `LocalApiClient` against a fake daemon on a
  temporary unix socket. Never test against the real socket.
- Code that touches nativeapi (tray, window) has no automated tests. It needs a
  manual check in the running app; ask the maintainer to do it. The clipboard
  can be checked with `wl-paste`.

## Code style

- Never use the `void` operator to discard a value or a future. Call the
  expression as a plain statement, and attach `.catchError(...)` where errors
  need handling.
- Keep code, comments, commit messages and docs in English.

## Git

- Do not commit or push unless the maintainer asks for that specific change.
- Do not add AI attribution (`Co-Authored-By` trailers, "Generated with"
  footers) to commits or PRs.
