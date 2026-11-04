# Changelog

All notable changes to Tailscale for Linux. Versions follow
[Semantic Versioning](https://semver.org); a version with a suffix such as `-beta` is a
pre-release. Each section below becomes the notes of its GitHub release.

## [Unreleased]

### Added

- Renew in the account menu of the main window, with when the key expires ("Expires
  in 18 hours", "Expired"), like the macOS app.
- Renew in the tray menu when the session has ended but the account is still on this
  computer. Its login page opens or is copied, as Settings → Login links says.
- Settings → Settings recommends installing `wl-clipboard` on Wayland when `wl-copy`
  is missing.

### Fixed

- On Wayland, copying from the tray (a device's IP, a login link) left the clipboard
  empty: the compositor ignores a window without focus. The app now copies with
  `wl-copy` (`wl-clipboard`), and a notification says what was copied. Without
  `wl-copy`, the IP or login link shows in the window, with a Copy button.
- Settings → Accounts: a logged-out current account (for example after its key
  expired) has a Log In button. Before, only a disabled Log Out button showed, and
  there was no way to log back in from the app.

## [0.2.0] - 2026-11-03

### Added

- A Copy link button next to each button that opens a web page (Admin Console, help
  pages, Tailnet Lock, Report an Issue, Release Notes), to open it in a browser other
  than the default one.
- Settings → Login links: the login page for Add Account and Renew can be copied to the
  clipboard, with a notification, instead of opening in the default browser.

## [0.1.1] - 2026-11-02

### Fixed

- The selected device in the main window no longer shows over the search field and the
  header when it is scrolled out of the list. The same fix applies to the account list
  in Settings.
- The selected section (Devices, Exit Nodes) in the main window's sidebar now has its
  highlight; it was hidden under the sidebar's background.

## [0.1.0] - 2026-11-01

First release.

### Added

- A tray icon that shows whether Tailscale is connected, with a white or a black icon
  for dark and light panels.
- A tray menu like the macOS menu bar app: connect and disconnect, switch accounts, copy
  this device's or another device's IP, pick an exit node, and see files being received.
- The main window (Open Tailscale): devices grouped into pinned, yours, tagged and each
  other user's, with search; a device's addresses, OS and key expiry; Ping with a latency
  graph and the connection path; Taildrop to send files to your devices, picked or
  dragged in; and exit nodes.
- Files sent to this computer with Taildrop are saved to the Downloads folder, with a
  desktop notification.
- Settings: Accounts (add, switch, log out, renew, remove), Settings (incoming
  connections, Tailscale DNS with a DNS dialog, subnets, launch at login, tray icon,
  Tailnet Lock status) and About, with Check for Updates.
- An access check on start that shows the command making you the Tailscale operator.
  When a profile change takes operator rights away, the app restores them with pkexec.
- In-app updates from About: Check for Updates finds a newer release on GitHub, Update
  replaces the copy `install.sh` installed (the old one stays if anything fails), and
  Restart starts it.
- An installer that installs the newest GitHub release for the current user, with a
  menu entry and icon.
