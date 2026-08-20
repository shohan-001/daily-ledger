# DailyLedger

A deliberately small offline budget tracker for daily cash-and-card spending.
Everything lives in one local SQLite file. No login, no cloud, no network calls,
one currency, five screens.

- **Developer:** [Shohan](https://github.com/shohan-001)
- **Repository:** https://github.com/shohan-001/daily-ledger
- **Clone:** `git clone https://github.com/shohan-001/daily-ledger.git`
- **Releases:** APK (Android) and `.deb` (Linux) are attached to [GitHub Releases](https://github.com/shohan-001/daily-ledger/releases), not stored in this repo.

Built as a drastically simplified answer to [Cashew](https://github.com/jameskokoska/Cashew):
same core idea (log spending, watch a budget), none of the sync, themes,
multi-currency or translation machinery.

## What it does

- **Home** — total balance with a per-account breakdown, this month's spend
  against the overall budget, a big Add Transaction button, quick-add presets,
  and the last 10 transactions.
- **Add/Edit transaction** — amount, expense/income/transfer, account, category,
  date (defaults to today), optional note. One-tap presets like `Bus fare · 50`
  pre-fill the form.
- **History** — full list with period / account / category filters and a search
  over note text, grouped by day with per-day totals.
- **Budgets** — one monthly limit per category plus an overall limit, each with a
  spent-so-far bar, and a hand-drawn spend-by-category bar chart.
- **Settings** — manage accounts, categories, quick-add presets and monthly
  recurring rules; export every transaction to CSV; see where the database file
  lives.

Recurring rules are checked **once at launch** and always ask for confirmation —
nothing is posted silently, and there are no background timers.

## Deliberately not included

Multi-currency, Firebase/Drive sync, shared budgets, theme marketplace,
in-app translations, home-screen widgets, notifications, and
auto-categorisation. Backup is "copy the `.db` file" plus CSV export.
Android can optionally lock the app with fingerprint / face / PIN.

## First-time setup

1. **Flutter (stable).** A copy already lives on the project drive:

```bash
export PATH="/run/media/shohan/New Volume/sdk/flutter-stable/bin:$PATH"
export PUB_CACHE="/run/media/shohan/New Volume/sdk/pub-cache"
```

Add those two lines to `~/.bashrc` if you want them permanent. From scratch
instead:

```bash
git clone --depth 1 -b stable https://github.com/flutter/flutter.git ~/flutter
export PATH="$HOME/flutter/bin:$PATH"   # add this to ~/.bashrc
flutter config --enable-linux-desktop
```

2. **Linux build toolchain** (Debian/Kali). Needs sudo, once:

```bash
sudo apt update
sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev libsqlite3-0
```

`clang` and `libsqlite3-0` are typically already present. `cmake`, `pkg-config`
and `libgtk-3-dev` are the ones `flutter run` still needs.

3. **Platform folders** (`linux/`, `windows/`) are already in this repo. On a
   fresh copy of just `lib/` you would generate them with:

```bash
flutter create --platforms=linux,windows --project-name dailyledger .
flutter pub get
```

4. **Run it:**

```bash
flutter pub get
flutter run -d linux
```

Then `flutter analyze` to confirm a clean tree.

## Phone APK (Android)

Same app and schema. Data on the phone stays **on the phone** — it does not sync with Linux.

Install this file on a typical 64-bit phone:

`package/apk/dailyledger-0.2.0.apk`

Copy it over USB / Drive / KDE Connect, open it, and allow “Install unknown apps” if Android asks.

To install an update later, bump `version:` in `pubspec.yaml` (for example `0.1.1+2`) and rebuild. Android upgrades in place if the same key is used (`android/keystore/dailyledger.jks` — keep that file).

```bash
export PATH="/run/media/shohan/New Volume/sdk/flutter-stable/bin:$PATH"
export JAVA_HOME=/home/shohan/.local/opt/jdk-17
export ANDROID_HOME=/home/shohan/.local/opt/android-sdk
export PUB_CACHE="/run/media/shohan/New Volume/sdk/pub-cache"
export GRADLE_USER_HOME="/run/media/shohan/New Volume/sdk/gradle"
flutter build apk --release --split-per-abi
cp build/app/outputs/flutter-apk/app-arm64-v8a-release.apk package/apk/dailyledger-0.2.0.apk
```

iOS needs a Mac; the `ios/` folder is ready for that later.

## Building the .deb

See [PACKAGING.md](PACKAGING.md). Short version:

```bash
flutter build linux --release --split-debug-info=./debug_info --obfuscate
./package/build_deb.sh 0.2.0
sudo dpkg -i package/build/dailyledger_0.2.0_amd64.deb
```

## Where your data lives

| What | Path |
| --- | --- |
| Database (Linux) | `~/.local/share/dailyledger/dailyledger.db` |
| Database (Android) | app-private storage (path shown in Settings) |
| CSV exports (Linux) | `~/Documents/dailyledger-<date>-<time>.csv` |
| CSV exports (Android) | app documents folder (path shown after export) |

Copying the `.db` file, or using **Send / Receive over Wi-Fi** in Settings, is
a complete backup. Phone and Linux do not share data automatically.

## Syncing Linux and the phone

There is no cloud account. Settings → **Sync Linux ↔ phone**:

1. **Same Wi-Fi (easiest):** on the device you just used, tap **Send over Wi-Fi**.
   On the other device tap **Receive over Wi-Fi** and type the IP + PIN.
   That replaces the receiving copy with the sending one.
2. **File:** **Save / Share backup .db**, copy the file (USB, Drive, Bluetooth),
   then **Import backup .db** on the other device.

Always send from the copy you last edited. The two devices do not merge.

## Code layout

Flat on purpose — the whole app is readable in an evening.

| File | What's in it |
| --- | --- |
| `lib/main.dart` | Startup: open the database, build the store, run the app |
| `lib/constants.dart` | Currency, palette, theme, date/money formatting, icon map |
| `lib/models.dart` | The five entities plus `Preset`, as plain immutable classes |
| `lib/db.dart` | Schema, first-run seed data, every SQL statement |
| `lib/store.dart` | The single `ChangeNotifier` holding cached lists |
| `lib/backup.dart` | Writes a shareable `.db` snapshot |
| `lib/lan_sync.dart` | Same-Wi-Fi send/receive of that snapshot |
| `lib/csv_export.dart` | CSV writer |
| `lib/recurring.dart` | The "these rules are due" launch dialog |
| `lib/screens/` | One file per screen, plus the dialogs used by Settings |
| `lib/widgets/common.dart` | Panel, progress bar, month switcher, transaction row |
| `lib/widgets/category_bars.dart` | The `CustomPainter` bar chart |
| `package/` | `.deb` build script, `.desktop` entry, icon |

### Dependencies, and why each one is there

| Package | Reason |
| --- | --- |
| `provider` | Wiring one `ChangeNotifier` into the widget tree |
| `sqlite3` | Direct SQLite access, no code generation (system `libsqlite3` on Linux) |
| `sqlite3_flutter_libs` | Bundles SQLite inside the Android/iOS app (phones have no system copy) |
| `path` / `path_provider` | Database and export paths |
| `file_selector` | Pick a `.db` backup to import |
| `share_plus` | Send that backup off the phone |

No `drift`, no `fl_chart`, no `intl`, no icon or font packs, no animation
packages. Money and date formatting are ~30 lines in `constants.dart`, and the
chart is a `CustomPainter`.

## Data model

Six tables, and that is the whole schema:

- `accounts` — name, starting balance, derived current balance. Seeded with
  Cash and Bank Card; add or rename more from Settings.
- `categories` — name, expense/income, icon key. Seeded with boarding/uni
  defaults (Food, Groceries, Boarding/Rent, Transport, Mobile/Data, Education,
  Entertainment, Savings, Other, plus a few income ones). All editable.
- `transactions` — amount, type, account, category, date, note, `is_recurring`.
  Transfers additionally use `to_account_id`, which is the one column added
  beyond the original sketch — a transfer needs a destination to mean anything.
- `recurring_rules` — monthly only: template amount/type/account/category/note,
  day of month, next due date, active flag.
- `budgets` — one `monthly_limit` per category; the row with a `NULL` category
  is the overall limit. No rollover, no custom periods.
- `presets` — the quick-add templates. This is the one extra table, needed to
  store presets you define yourself.

`accounts.current_balance` is derived: it is recomputed from the transaction
table after every write, so the two can never drift apart.

## Customising

- **Currency:** change `kCurrencySymbol` in `lib/constants.dart`.
- **Colours:** the palette constants at the top of the same file.
- **Categories / accounts / presets / recurring rules:** all editable in the app.

## Gotchas

- The project currently sits on an NTFS volume (`/run/media/...`). Flutter builds
  work there but are slower and occasionally trip over permissions; if a build
  behaves strangely, copy the project to an ext4 path and build again.
- If the app starts with "could not start" and mentions libsqlite3, install it:
  `sudo apt install libsqlite3-0`.
