# Tailscale for Linux

A system tray client for [Tailscale](https://tailscale.com) on Linux, modelled
on the official macOS app. Built with Flutter.

This is an unofficial project and is not affiliated with Tailscale Inc.

## Features

- **Tray icon** that shows whether Tailscale is connected.
- **Tray menu**, laid out like the macOS menu bar app:
  - **Connected**: connect or disconnect.
  - **Renew Session…**: shown after the key expired, under when it did
    ("Expired 1 day ago"). Logs the account in again.
  - **Account**: the current account, with a submenu to switch between
    accounts that `tailscaled` knows about.
  - **This Device**: name and Tailscale IP. Click to copy the IP.
  - **Network Devices**: your devices and other tailnet devices, online first.
    Click to copy a device's IP.
  - **Exit Nodes**: pick an exit node or turn it off.
  - **Settings…**, **Open Tailscale** and **Quit**.
- **Main window** (Open Tailscale), shown while connected:
  - **Devices**: searchable, grouped into pinned, yours, tagged and each
    other user's. A device's details show its addresses (click to copy), OS
    and key expiry, and let you pin it to the top.
  - **Ping**: pings a device once a second and graphs the latency, with
    whether the connection is direct or relayed.
  - **Taildrop**: send files to your own devices, picked with the desktop's
    file dialog (kdialog or zenity) or dragged onto the device.
  - **Exit Nodes**: pick an exit node.
- **Receiving files**: files sent to this computer with Taildrop are saved to
  your Downloads folder, with a desktop notification (`notify-send`).
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
- On Wayland, `wl-copy` (the `wl-clipboard` package) to copy from the tray:
  a device's IP, or a login link when Settings → Login links is Copy. Without
  it, the IP or link shows in the window, with a Copy button.

## Install

Install the newest release for your user:

```sh
curl -fsSL https://raw.githubusercontent.com/NuclleaR/tailscale-linux/main/install.sh | bash
```

It puts the app in `~/.local/share/tailscale-linux`, the `tailscale-linux`
command in `~/.local/bin` and a **Tailscale** entry in the app menu. Remove it
with:

```sh
curl -fsSL https://raw.githubusercontent.com/NuclleaR/tailscale-linux/main/install.sh | bash -s -- --uninstall
```

To update, open **Settings… → About → Check for Updates**: the app downloads
the new release, replaces the installed copy (the old one stays if anything
fails) and restarts. Only a copy installed with `install.sh` updates itself.

The app starts in the tray with its window hidden. Open the window with
**Open Tailscale** or **Settings…**. Closing the window only hides it; use
**Quit** to exit.

**Launch Tailscale at login** writes
`~/.config/autostart/tailscale_linux.desktop` pointing at the binary that is
running. If you move the app, turn the option off and on again. The app's own
settings live in `~/.config/tailscale_linux/settings.json`.

## Building

You need the Flutter SDK (stable, Dart 3.13 or newer) and the usual Flutter
Linux toolchain: `clang`, `cmake`, `ninja`, `pkg-config` and the GTK 3, X11
and Xi development files. `mise install` sets up Flutter, CMake, Ninja and
`just` from `mise.toml`.

```sh
just run              # debug build, with hot reload
just build            # release build in build/linux/x64/release/bundle/
just install-local    # install that build the way install.sh does
```

Copy the whole `bundle/` directory if you move a build: the binary needs
`lib/` and `data/` next to it.

## Development

```sh
just check    # dart format check, flutter analyze, flutter test
just fmt      # format lib/ and test/
just --list   # everything else
```

## Releasing

1. Set the new `version` in `pubspec.yaml` (no build number) and add a
   `## [<version>] - <date>` section to `CHANGELOG.md`: it becomes the release
   notes.
2. Commit, then run `just release`. It tags `v<version>` and pushes the tag.
3. The **Release** workflow checks the tag against `pubspec.yaml`, runs the
   tests, builds `tailscale-linux-x64.tar.gz` and publishes the GitHub
   release. A version with a suffix, such as `0.2.0-beta`, becomes a
   pre-release.

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
| `POST /localapi/v0/ping` | Ping (disco pings) |
| `GET /localapi/v0/file-targets` | which devices Taildrop can send to |
| `PUT /localapi/v0/file-put/<id>/<name>` | sending a file |
| `GET`, `DELETE /localapi/v0/files/…` | receiving files |
| `POST /localapi/v0/check-prefs` | the access check (`403` means no write access) |

One step runs the CLI: when a profile change leaves this user without
operator rights, the app runs `pkexec tailscale set --operator=<user>`, which
asks for your password.

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
    taildrop_receiver.dart   saves received files to Downloads
    operator.dart            restores the operator with pkexec
  main_window/
    main_window.dart         header, sidebar and sections
    device_list.dart         device groups, search, sorting (unit tested)
    devices_view.dart        the device list and selection
    device_details.dart      one device's addresses and details
    ping_section.dart        the Ping graph; pinger.dart runs the pings
    taildrop_section.dart    sending files
    exit_nodes_view.dart     the Exit Nodes section
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
  update/
    update.dart              GitHub releases, versions, installing an archive
    update_controller.dart   Check for Updates in About
  platform/
    desktop.dart             XDG folders, opening URLs, notifications
    autostart.dart           the XDG autostart entry
    file_picker.dart         kdialog / zenity file dialog
linux/runner/                GTK runner: window starts hidden, close hides it
assets/tray/                 tray icons (SVG sources and rendered PNGs)
assets/app_icon.*            the menu entry's icon
install.sh                   installer for the newest GitHub release
justfile                     dev commands (just --list)
.github/workflows/release.yml  builds and publishes a release on a v* tag
```

## Known limitations

- It has not been verified that `tailscaled` sends a notification when a peer
  goes online or offline, so the device list may lag until the next state
  change.
