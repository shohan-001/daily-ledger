# Packaging DailyLedger

Every command below is run from the project root. Copy-paste and go; nothing
here needs to be re-derived after a code change.

## Prerequisites (once)

```bash
sudo apt update
sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev libsqlite3-0 dpkg-dev
flutter config --enable-linux-desktop
```

If `linux/` does not exist yet (fresh clone of source only), generate the runner
scaffolding first — it will not touch existing files:

```bash
flutter create --platforms=linux,windows --project-name dailyledger .
flutter pub get
```

This tree already includes `linux/` and `windows/`.

## 1. Build the release bundle

```bash
flutter build linux --release --split-debug-info=./debug_info --obfuscate
```

- `--split-debug-info=./debug_info` writes the symbol files outside the app, so
  the shipped binary carries no debug symbols. Keep `debug_info/` if you ever
  need to read a stack trace from a release build.
- `--obfuscate` strips Dart symbol names from the binary.
- Output: `build/linux/x64/release/bundle/` containing the `dailyledger`
  executable, `lib/`, and `data/`.

Never ship the debug build; it is several times larger and slower.

## 2. Build the .deb

```bash
./package/build_deb.sh 0.2.0
```

Pass the version as the first argument (it defaults to `0.2.0`). To set the
maintainer field without editing the script:

```bash
DEB_MAINTAINER="Your Name <you@example.com>" ./package/build_deb.sh 0.2.0
```

The script:

1. Verifies `build/linux/x64/release/bundle/dailyledger` exists.
2. Stages the standard layout under `package/build/dailyledger_<version>_amd64/`:
   - `DEBIAN/control`
   - `usr/lib/dailyledger/` — the whole Flutter bundle
   - `usr/bin/dailyledger` — a two-line launcher on `PATH`
   - `usr/share/applications/dailyledger.desktop` — app-menu entry
   - `usr/share/icons/hicolor/scalable/apps/dailyledger.svg` — icon
3. Writes `control` with package `dailyledger`, architecture `amd64`, the
   computed installed size, and `Depends: libc6, libstdc++6, libgtk-3-0,
   libsqlite3-0`.
4. Runs `dpkg-deb --root-owner-group --build`.

Result: `package/build/dailyledger_<version>_amd64.deb`.

## 3. Install, verify, remove

```bash
sudo dpkg -i package/build/dailyledger_0.2.0_amd64.deb
sudo apt-get install -f            # only if a dependency is missing

dpkg -L dailyledger                # what was installed where
dailyledger                        # run from a terminal
sudo apt remove dailyledger        # uninstall
```

The app should also appear in the desktop app menu as "DailyLedger". If the icon
does not refresh immediately:

```bash
sudo gtk-update-icon-cache -f /usr/share/icons/hicolor || true
sudo update-desktop-database || true
```

Uninstalling never touches your data: `~/.local/share/dailyledger/dailyledger.db`
stays put, so reinstalling picks up exactly where you left off.

## Rebuild loop after a code change

```bash
flutter build linux --release --split-debug-info=./debug_info --obfuscate \
  && ./package/build_deb.sh 0.2.1 \
  && sudo dpkg -i package/build/dailyledger_0.2.1_amd64.deb
```

Bump the version each time so `dpkg` treats it as an upgrade. Keep the version
in `pubspec.yaml`, `kAppVersion` in `lib/constants.dart`, and the argument above
in sync.

## Windows `.exe`

Flutter cannot cross-compile Windows from Linux. Build on a Windows PC, or let
GitHub Actions do it (this repo has `.github/workflows/windows.yml`).

### GitHub Actions (from this Kali machine)

```bash
git add .github/workflows/windows.yml lib/db.dart windows/runner/main.cpp PACKAGING.md
git commit -m "Add Windows exe build via GitHub Actions."
git push origin main
```

Then on GitHub: **Actions → Windows exe → Run workflow**. Download the
`dailyledger-windows-x64` zip. Unzip the folder and run `dailyledger.exe`
(keep `data/`, `*.dll`, and the exe together).

A tag `v0.2.5` (or later) also attaches that zip to the GitHub Release.

### On a Windows PC

```bat
flutter config --enable-windows-desktop
flutter pub get
flutter build windows --release
```

Output folder: `build\windows\x64\runner\Release\`

Zip **the whole folder** (not only the exe). `sqlite3_flutter_libs` places
`sqlite3.dll` next to `dailyledger.exe`. Do not add Linux-only SQLite code
paths; Windows loading lives in `lib/db.dart` behind `Platform.isWindows`.
