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
  dev dependencies and code generators. Approved so far: `tray_manager`,
  `window_manager`, `desktop_drop` (drag and drop for Taildrop).
- **Desktop tools run as processes, not packages**: `xdg-open`,
  `notify-send`, `kdialog`/`zenity` (file dialog), `pkexec`.
- **One window, two screens**: the main window and the settings window share
  the single native window; `AppScreen` in `main.dart` picks which shows.
- **Releases follow mp3directcutlinux** (the maintainer's other app): a `v*`
  tag that matches `pubspec.yaml`'s `version` (no build number) and a
  `CHANGELOG.md` section for it; `.github/workflows/release.yml` publishes
  `tailscale-linux-x64.tar.gz`; `install.sh` installs the newest release into
  `~/.local/share/tailscale-linux`; About's Check for Updates replaces only
  that copy.

## Commands

```sh
flutter analyze
flutter test
dart format lib test
flutter build linux --debug
build/linux/x64/debug/bundle/tailscale_linux    # run the built app
```

The `justfile` wraps these (`just --list`) for the maintainer. Before
reporting a change as done, run `flutter analyze` and `flutter test`, and
format the code with `dart format`.

Never run `just release`, push a tag or install into `~/.local` unless the
maintainer asks: a tag publishes a release. Test `install.sh` with
`XDG_DATA_HOME`/`XDG_BIN_HOME` pointing at a temporary folder and
`TAILSCALE_LINUX_ARCHIVE_URL=file://…`.

A user-visible change gets a line in `CHANGELOG.md` under the next version.

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
- `lib/main_window/`: the main window. `device_list.dart` is a pure function
  (groups, search, sorting) with tests, like `buildTrayMenu`. Devices and exit
  nodes show only while the backend is `Running`: in other states the status
  still carries stale peers.
- `lib/tailscale/taildrop_receiver.dart`: saves received files to the XDG
  Downloads folder on `FilesWaiting` bus events and on start.
- `lib/update/`: in-app updates. `update.dart` is copied from
  mp3directcutlinux's `lib/core/update.dart` (names changed); keep the two
  alike. `AppInstall` decides whether this copy is the installed one.
- `lib/settings/`: the settings window. User actions go through
  `runAction` (`widgets.dart`), which shows a failure in a snack bar;
  destructive ones ask first with `confirm`.
- `lib/platform/`: the desktop around the app: XDG config directory,
  `xdg-open`, the autostart entry. No packages for these.
- `lib/main.dart`: wiring, and dispatch of `TrayCommand`s. A `403` from a tray
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
- `NotifyInitialNetMap` (8) is no longer supported either. The netmap is not
  available on the bus; read what is needed from dedicated endpoints, such as
  `dns-config` for the DNS settings.
- `profiles/` needs write access, even for `GET`. `refresh` must not fail
  because of it: status and prefs are readable by anyone, and a stale state
  shows the previous account's data. A `403` there sets `canWrite` to false,
  and `main.dart` then shows the access page.
- The operator (`OperatorUser`) is a per-profile pref, and a new profile has
  none. Add Account, Log Out and removing the current account all switch to
  a new profile, and switching can land on a profile without one. The
  controller compares `OperatorUser` before and after, and when it was lost,
  sets it again as root with `pkexec tailscale set --operator=<user>`
  (`lib/tailscale/operator.dart`). It is the only place the CLI is run.
- Peer `ID` in `status` is the stable node ID that `ExitNodeID` expects.
- Accounts: `logout` logs the current account out and deletes its profile.
  `DELETE profiles/<id>` only forgets the profile; the node stays registered.
  `PUT profiles/` switches to a new, empty profile.
- A peer's `Online` means "connected to the coordination server". An iPhone
  in the background is offline yet answers over the tunnel, so the UI shows
  `Node.reachable`: `Online`, a WireGuard handshake within 3 minutes, or a
  reply to this app's ping within 3 minutes. The app's pings are disco pings
  and cause no handshake, so the controller remembers replies itself. The bus
  does not report handshakes: status is re-read every 60 s while the window
  is open (`AppLifecycleState` `resumed` or `inactive`) and once when it
  opens. Closing the window hides it (`hidden`): then only the tray is up,
  and nothing is polled. A running ping also stops on `hidden`.
- `ping` reports a failed ping in `Err` with status 200, and waits for a
  reply as long as the request is open: `LocalApiClient.ping` aborts it after
  a timeout.
- Taildrop: `file-targets` lists the devices files can go to. `file-put`
  takes the escaped file name as a path segment. Received files wait in
  tailscaled (`files/`, write access needed) until fetched and deleted.
- The bus fields the app uses for receiving, `FilesWaiting` and
  `IncomingFiles` (progress), are marked deprecated in tailscaled 1.104 in
  favour of the `files/?waitsec=` long poll, which reports no progress. The
  maintainer chose to keep them; if they disappear, receiving stops
  triggering. tailscaled sends its last `IncomingFiles` for a file before
  dropping it from the list, and nothing after, so a finished file must be
  recognised (`Done`, or all bytes in) or cleared when the receiver saves
  it; it never disappears from the bus on its own. Progress comes at most
  once a second. Events carrying only `IncomingFiles`/`OutgoingFiles` do not
  trigger a refresh: they arrive often during a transfer.
- Login pages arrive on the bus as `BrowseToURL` (and in `status.AuthURL`).
  The controller opens one only after this app asked for a login, so logins
  started by the CLI or another client do not open the browser.
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
- `test/local_api_test.dart` runs `LocalApiClient` against a fake daemon
  (`test/fake_daemon.dart`) on a temporary unix socket. Never test against the
  real socket.
- `test/tailscale_controller_test.dart` keeps a fake IPN bus open and writes
  events to it. Set `bufferOutput = false` on that response, or events are not
  sent until it closes. Close the bus and let the controller see it end before
  the client is closed; closing the client mid-read fails the test.
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
