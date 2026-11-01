#!/usr/bin/env bash
# Installs the newest Tailscale for Linux release from GitHub for the current user:
#
#   curl -fsSL https://raw.githubusercontent.com/NuclleaR/tailscale-linux/main/install.sh | bash
#
# and removes it again with:
#
#   curl -fsSL https://raw.githubusercontent.com/NuclleaR/tailscale-linux/main/install.sh | bash -s -- --uninstall
#
#   app           $XDG_DATA_HOME/tailscale-linux (default ~/.local/share)
#   command       $XDG_BIN_HOME/tailscale-linux (default ~/.local/bin), a symlink
#   menu entry    $XDG_DATA_HOME/applications/dev.serhii.tailscale_linux.desktop
#
# The menu entry is named after the app id: on Wayland the dock ignores the window icon
# and finds the app's name and icon through it. TAILSCALE_LINUX_ARCHIVE_URL installs the
# given archive instead of the newest release (file:// URLs work too).
#
# This installs the app only. It needs tailscaled running, with you as its operator:
#
#   sudo tailscale set --operator=$USER
set -euo pipefail

repo=NuclleaR/tailscale-linux
asset=tailscale-linux-x64.tar.gz
app_id=dev.serhii.tailscale_linux
data="${XDG_DATA_HOME:-$HOME/.local/share}"
dest="$data/tailscale-linux"
link="${XDG_BIN_HOME:-$HOME/.local/bin}/tailscale-linux"
entry="$data/applications/$app_id.desktop"

uninstall() {
  rm -rf "$dest"
  if [[ -L "$link" ]]; then rm "$link"; fi
  rm -f "$entry"
}

if [[ "${1:-}" == "--uninstall" ]]; then
  uninstall
  echo "Removed Tailscale for Linux."
  exit 0
fi

url="${TAILSCALE_LINUX_ARCHIVE_URL:-}"
if [[ -z "$url" ]]; then
  # The newest release, pre-releases included (the "latest" endpoint skips them).
  url="$(curl -fsSL "https://api.github.com/repos/$repo/releases?per_page=1" |
    grep -o "\"browser_download_url\": *\"[^\"]*/$asset\"" | head -n 1 | grep -o 'https://[^"]*' || true)"
  if [[ -z "$url" ]]; then
    echo "No release of $repo has $asset yet." >&2
    exit 1
  fi
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
echo "Downloading $url"
curl -fL --progress-bar -o "$tmp/$asset" "$url"
tar -xzf "$tmp/$asset" -C "$tmp"
if [[ ! -x "$tmp/tailscale-linux/tailscale_linux" ]]; then
  echo "The archive has no tailscale-linux/tailscale_linux." >&2
  exit 1
fi

uninstall
mkdir -p "$data" "$(dirname "$link")" "$(dirname "$entry")"
mv "$tmp/tailscale-linux" "$dest"
ln -s "$dest/tailscale_linux" "$link"
cat > "$entry" <<EOF
[Desktop Entry]
Type=Application
Name=Tailscale
Comment=Tailscale system tray client
Exec=$dest/tailscale_linux
Icon=$dest/data/flutter_assets/assets/app_icon.png
Terminal=false
Categories=Network;
StartupWMClass=$app_id
EOF

echo "Installed Tailscale for Linux to $dest"
case ":$PATH:" in
  *":$(dirname "$link"):"*) echo "Start it from the app menu or with: tailscale-linux" ;;
  *) echo "Start it from the app menu; $(dirname "$link") is not on PATH, so the tailscale-linux command needs it added." ;;
esac
echo "To start it on login, turn on Settings > Launch Tailscale at login in the app."
