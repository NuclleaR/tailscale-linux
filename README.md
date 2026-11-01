# Tailscale for Linux

A system tray client for [Tailscale](https://tailscale.com) on Linux, modelled
on the official macOS app. Built with Flutter.

This is an unofficial project and is not affiliated with Tailscale Inc.

## Features

- **Tray icon** that shows whether Tailscale is connected.
- **Tray menu**, laid out like the macOS menu bar app:
  - **Connected**: connect or disconnect.
  - **Account**: the current account, with a submenu to switch between
    accounts that `tailscaled` knows about.
  - **This Device**: name and Tailscale IP. Click to copy the IP.
  - **Network Devices**: your devices and other tailnet devices, online first.
    Click to copy a device's IP.
  - **Exit Nodes**: pick an exit node or turn it off.
  - **Settings…** and **Quit**.
- **Settings window** with the Accounts pane: tailnet, email, login status,
  control server and key expiry for each account.
- **Live updates**: the app subscribes to `tailscaled` notifications instead of
  polling.
- **Access check** on start. Without operator rights, the app shows the
  command that grants them, plus a Recheck button.

## Requirements

- Linux with a StatusNotifierItem system tray. KDE Plasma works out of the box.
  GNOME needs the AppIndicator extension.
- `tailscaled` running, with its socket at `/var/run/tailscale/tailscaled.sock`.
- Your user set as the Tailscale operator, so the app can change settings
  without root. Run this once:

  ```sh
  sudo tailscale set --operator=$USER
  ```

  Without it the app can still show status, but connect, exit node and
  account switching are refused by `tailscaled`.

## Building

You need the Flutter SDK (stable, Dart 3.13 or newer) and the usual Flutter
Linux toolchain: `clang`, `cmake`, `ninja`, `pkg-config` and the GTK 3, X11
and Xi development files.

```sh
flutter pub get
flutter run -d linux                # run in debug mode
flutter build linux --release       # release build
```

The release binary is
`build/linux/x64/release/bundle/tailscale_linux`. Copy the whole `bundle/`
directory if you move it: the binary needs `lib/` and `data/` next to it.

The app starts in the tray with its window hidden. Open the window with
**Settings…**. Closing the window only hides it; use **Quit** to exit.

## Development

```sh
flutter analyze
flutter test
dart format lib test
```

### How it works

The app talks to `tailscaled` through its LocalAPI, the HTTP API that the
`tailscale` CLI itself uses, served over the unix socket
`/var/run/tailscale/tailscaled.sock`. It does not run the CLI.

| Endpoint | Used for |
|---|---|
| `GET /localapi/v0/watch-ipn-bus` | the stream of state changes that triggers refreshes |
| `GET /localapi/v0/status` | backend state, this device, peers, users |
| `GET /localapi/v0/profiles/`, `/profiles/current` | accounts |
| `POST /localapi/v0/profiles/<id>` | switching accounts |
| `PATCH /localapi/v0/prefs` | connect or disconnect, exit node |
| `GET /localapi/v0/prefs` + `POST /localapi/v0/check-prefs` | the access check (`403` means no write access) |

### Project layout

```
lib/
  main.dart                  wiring: tray, window, controllers
  app_window.dart            show and focus the native window
  access/                    operator access check and its screen
  tailscale/
    local_api.dart           LocalAPI client over the unix socket
    status.dart              status and profile models
    tailscale_controller.dart  app state, kept current from the IPN bus
  tray/
    tray_menu.dart           the tray menu as plain data (unit tested)
    tray_presenter.dart      turns that data into the native tray menu
  settings/accounts_page.dart  the Accounts pane
linux/runner/                GTK runner: window starts hidden, close hides it
assets/tray/                 tray icons (SVG sources and rendered PNGs)
```

## Known limitations

- The Accounts pane has no Log Out or Add Account buttons yet. The Settings
  and About panes from the macOS app are not implemented.
- The tray icons are white, so they suit dark panels and are hard to see on
  light ones.
- It has not been verified that `tailscaled` sends a notification when a peer
  goes online or offline, so the device list may lag until the next state
  change.
- The app does not start on login by itself.
