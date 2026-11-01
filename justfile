# Debug build of the Linux app, with hot reload (r) and hot restart (R) in the terminal.
run:
    mise exec -- flutter run -d linux

# Unit and widget tests.
test:
    mise exec -- flutter test

# The Dart analyzer.
analyze:
    mise exec -- flutter analyze

# Formats lib/ and test/ in place.
fmt:
    mise exec -- dart format lib test

# Formatting, the analyzer and the tests: run before a commit.
check:
    mise exec -- dart format --output=none --set-exit-if-changed lib test
    mise exec -- flutter analyze
    mise exec -- flutter test

# Release build in build/linux/x64/release/bundle/.
build:
    mise exec -- flutter build linux --release

# The release archive, as CI builds it: build/tailscale-linux-x64.tar.gz.
package: build
    tar -C build/linux/x64/release --transform 's,^bundle,tailscale-linux,' \
        -czf build/tailscale-linux-x64.tar.gz bundle

# Installs this checkout's release build the way install.sh installs a release.
install-local: package
    TAILSCALE_LINUX_ARCHIVE_URL="file://{{justfile_directory()}}/build/tailscale-linux-x64.tar.gz" bash install.sh

# Removes what install.sh installed.
uninstall:
    bash install.sh --uninstall

# Removes build/, .dart_tool/ and linux/flutter/ephemeral/.
clean:
    mise exec -- flutter clean

# Bump `version` in pubspec.yaml, add its CHANGELOG.md section and commit first.
# Tags v<version> and pushes the tag; CI builds and publishes the release.
release:
    #!/usr/bin/env bash
    set -euo pipefail
    version="$(sed -n 's/^version: *//p' pubspec.yaml)"
    if ! grep -q "^## \[$version\]" CHANGELOG.md; then
      echo "CHANGELOG.md has no section for $version" >&2
      exit 1
    fi
    if ! git diff --quiet || ! git diff --cached --quiet; then
      echo "Commit your changes first" >&2
      exit 1
    fi
    git tag "v$version"
    git push origin "v$version"
    echo "Pushed v$version; CI publishes the release."
