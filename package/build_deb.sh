#!/usr/bin/env bash
#
# Builds package/build/dailyledger_<version>_amd64.deb from the Flutter Linux
# release bundle. Run `flutter build linux --release` first (see PACKAGING.md).
#
# Staging happens under /tmp so chmod actually sticks (the project lives on
# NTFS, which reports 777 and makes dpkg-deb refuse the control directory).
#
# Usage: ./package/build_deb.sh [version]

set -euo pipefail

PKG_NAME="dailyledger"
VERSION="${1:-0.2.4}"
ARCH="amd64"
MAINTAINER="${DEB_MAINTAINER:-Shohan <shohan@localhost>}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUNDLE="$ROOT/build/linux/x64/release/bundle"
OUT_DIR="$ROOT/package/build"
WORK="$(mktemp -d "/tmp/${PKG_NAME}-deb.XXXXXX")"
STAGE="$WORK/${PKG_NAME}_${VERSION}_${ARCH}"
DEB_NAME="${PKG_NAME}_${VERSION}_${ARCH}.deb"

cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

if [ ! -d "$BUNDLE" ]; then
  echo "error: release bundle not found at $BUNDLE" >&2
  echo "run this first:" >&2
  echo "  flutter build linux --release --split-debug-info=./debug_info --obfuscate" >&2
  exit 1
fi

if [ ! -x "$BUNDLE/$PKG_NAME" ]; then
  echo "error: $BUNDLE/$PKG_NAME is missing." >&2
  echo "the executable name must match the pubspec project name." >&2
  exit 1
fi

echo "==> staging $STAGE"
mkdir -p \
  "$STAGE/DEBIAN" \
  "$STAGE/usr/bin" \
  "$STAGE/usr/lib/$PKG_NAME" \
  "$STAGE/usr/share/applications" \
  "$STAGE/usr/share/icons/hicolor/scalable/apps"

cp -r "$BUNDLE/." "$STAGE/usr/lib/$PKG_NAME/"

# Thin launcher on PATH; the real binary keeps its data/ and lib/ neighbours.
cat > "$STAGE/usr/bin/$PKG_NAME" <<EOF
#!/bin/sh
cd /usr/lib/$PKG_NAME || exit 1
exec ./$PKG_NAME "\$@"
EOF

cp "$ROOT/package/$PKG_NAME.desktop" "$STAGE/usr/share/applications/"
cp "$ROOT/package/$PKG_NAME.svg" \
   "$STAGE/usr/share/icons/hicolor/scalable/apps/"

find "$STAGE" -type d -exec chmod 755 {} +
find "$STAGE/usr/share" -type f -exec chmod 644 {} +
chmod 755 "$STAGE/usr/bin/$PKG_NAME"
chmod 755 "$STAGE/usr/lib/$PKG_NAME/$PKG_NAME"
chmod 755 "$STAGE/DEBIAN"
chmod 644 "$STAGE/DEBIAN/control" 2>/dev/null || true

INSTALLED_SIZE="$(du -sk "$STAGE" | cut -f1)"

cat > "$STAGE/DEBIAN/control" <<EOF
Package: $PKG_NAME
Version: $VERSION
Section: utils
Priority: optional
Architecture: $ARCH
Depends: libc6, libstdc++6, libgtk-3-0, libsqlite3-0
Installed-Size: $INSTALLED_SIZE
Maintainer: $MAINTAINER
Description: Minimal offline personal budget tracker
 DailyLedger records daily cash and card spending in one local SQLite file.
 No cloud account. Optional same-Wi-Fi backup to a phone. Budgets, monthly
 recurring rules and CSV export.
EOF
chmod 644 "$STAGE/DEBIAN/control"

echo "==> building package"
mkdir -p "$OUT_DIR"
dpkg-deb --root-owner-group --build "$STAGE" "$WORK/$DEB_NAME"
cp -f "$WORK/$DEB_NAME" "$OUT_DIR/$DEB_NAME"

echo "==> done: $OUT_DIR/$DEB_NAME"
