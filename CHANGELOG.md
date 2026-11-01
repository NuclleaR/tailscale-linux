# Changelog

All notable changes to Tailscale for Linux. Versions follow
[Semantic Versioning](https://semver.org); a version with a suffix such as `-beta` is a
pre-release. Each section below becomes the notes of its GitHub release.

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
