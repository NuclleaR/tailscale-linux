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
- **Settings window** with three panes, as in the macOS app:
  - **Accounts**: tailnet, email, login status and key expiry for each
    account. Add an account (the login page opens in your browser), switch to
    another, log out, renew the key, or remove an account from this computer.
  - **Settings**: allow incoming connections, use Tailscale DNS (with a
    dialog listing the tailnet's search domains and split DNS routes), use
    Tailscale subnets, launch at login, the tray icon color, and whether
    Tailnet Lock is enabled.
  - **About**: app and `tailscaled` versions, a notice when a newer
    `tailscaled` exists, and links.
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

**Launch Tailscale at login** writes
`~/.config/autostart/tailscale_linux.desktop` pointing at the binary that is
running. If you move the bundle, turn the option off and on again. The app's
own settings live in `~/.config/tailscale_linux/settings.json`.

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
| `GET /localapi/v0/watch-ipn-bus` | the stream of state changes that triggers refreshes, and login page URLs |
| `GET /localapi/v0/status` | backend state, this device, peers, users, `tailscaled` version |
| `GET /localapi/v0/profiles/`, `/profiles/current` | accounts |
| `POST /localapi/v0/profiles/<id>` | switching accounts |
| `PUT /localapi/v0/profiles/` | adding an account (a new, empty profile) |
| `DELETE /localapi/v0/profiles/<id>` | removing an account from this computer |
| `POST /localapi/v0/login-interactive` | logging in, renewing the key |
| `POST /localapi/v0/logout` | logging out |
| `GET /localapi/v0/prefs` | the Settings pane |
| `PATCH /localapi/v0/prefs` | connect or disconnect, exit node, the Settings pane |
| `GET /localapi/v0/dns-config` | the DNS dialog |
| `GET /localapi/v0/tka/status` | Tailnet Lock status |
| `GET /localapi/v0/update/check` | whether a newer `tailscaled` exists |
| `POST /localapi/v0/check-prefs` | the access check (`403` means no write access) |

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
  settings/
    settings_window.dart     the window: Accounts, Settings and About tabs
    accounts_page.dart       the Accounts pane
    settings_page.dart       the Settings pane
    dns_dialog.dart          the DNS dialog behind Manage…
    about_page.dart          the About pane
    app_settings.dart        the app's own settings file
    widgets.dart             shared widgets and the error snack bar
  platform/
    desktop.dart             XDG config directory, opening URLs (xdg-open)
    autostart.dart           the XDG autostart entry
linux/runner/                GTK runner: window starts hidden, close hides it
assets/tray/                 tray icons (SVG sources and rendered PNGs)
```

## Known limitations

- The main window of the macOS app (Open Tailscale: devices, exit nodes,
  Taildrop) is not implemented yet.
- It has not been verified that `tailscaled` sends a notification when a peer
  goes online or offline, so the device list may lag until the next state
  change.
