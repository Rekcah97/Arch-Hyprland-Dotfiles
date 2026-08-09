# Arch Universal Updater

A fullscreen terminal dashboard that updates everything installed via
**Pacman**, **Yay (AUR)**, and **Flatpak** from a single interface — in the
spirit of `btop`, `htop`, `lazygit`, and `gitui`, but purpose-built for
keeping an Arch Linux system up to date.

Instead of scrolling package-manager output, Arch Universal Updater
redraws a live, in-place dashboard showing per-manager progress, current
package, build/download stage, system stats, and recently completed
packages — with retry, cleanup, notifications, and exportable reports
built in.

---

## Features

- Detects Pacman, Yay, and Flatpak automatically and updates all three
  from one dashboard
- Live, redraw-in-place fullscreen UI (no scrolling output) with hidden
  cursor and ANSI/Unicode box-drawing panels
- Per-manager overall + per-package progress bars, with stage-based
  progress for managers that don't expose byte-level percentages (AUR
  builds, Flatpak deploys)
- Continues past individual package failures instead of aborting the run
- Automatic retry for failed packages (configurable attempt count/delay)
- Manual retry-failed-only shortcut
- Detailed, timestamped logs with automatic archival
- Desktop notifications via `notify-send`
- Optional cleanup stage (orphan removal, unused Flatpak runtimes, pacman
  cache trimming) with freed-space reporting
- Four built-in themes (Default, Nord, Catppuccin, Dark), switchable live
- Fully configurable via plain-text config files
- Exportable plain-text update reports
- Modular, shellcheck-friendly Bash codebase — no single giant script

---

## Screenshots

> Run the dashboard on your own terminal to see it live — box-drawing and
> 256-color panels don't render well as static images in a repo. A
> `screenshots/` directory is included for you to drop your own captures
> into (e.g. `screenshots/dashboard.png`) if you want to showcase it in a
> fork.

---

## Installation

```bash
git clone https://github.com/yourname/arch-universal-updater.git
cd arch-universal-updater
chmod +x arch-updater.sh
./arch-updater.sh
```

There's nothing to compile and nothing to install system-wide — the
script runs in place. If you want it available as a regular command:

```bash
sudo ln -s "$(pwd)/arch-updater.sh" /usr/local/bin/arch-updater
```

## Dependencies

**Required:**

- `bash` >= 5.0
- `pacman` (present on any Arch system)
- Standard coreutils (`awk`, `sed`, `grep`, `df`, `date`, `mktemp`, `tput`)

**Optional (each feature degrades gracefully if missing):**

| Tool             | Used for                                              |
|------------------|--------------------------------------------------------|
| `yay`            | AUR package updates                                    |
| `flatpak`        | Flatpak updates                                        |
| `pacman-contrib` | `checkupdates` (safer update checks) and `paccache`     |
| `notify-send`    | Desktop notifications (`libnotify`)                     |
| `reflector`      | Mirrorlist refresh (`MIRROR_REFRESH=true`)              |
| `sudo`           | Privileged pacman/cleanup operations                    |

Install the optional pieces with:

```bash
sudo pacman -S --needed pacman-contrib libnotify reflector
yay -S --needed yay   # if you don't already have an AUR helper
sudo pacman -S --needed flatpak
```

---

## Usage

```bash
./arch-updater.sh                 # launch the interactive dashboard
./arch-updater.sh --check         # print pending update counts and exit
./arch-updater.sh --no-dashboard  # run updates with plain scrolling output
./arch-updater.sh --theme nord    # force a theme for this run
./arch-updater.sh --help          # usage information
```

On launch, the app runs through a startup checklist (connectivity, DNS,
pacman lock, disk space, package-manager detection) before scanning for
updates and opening the dashboard.

---

## Configuration

All configuration lives in plain-text files under `config/`.

### `config/config.conf`

The main settings file. Key groups:

- **Appearance** — `THEME`, `REFRESH_RATE`, `COMPACT_MODE`
- **Update behavior** — `ENABLE_PACMAN` / `ENABLE_YAY` / `ENABLE_FLATPAK`,
  `AUTO_RETRY`, `RETRY_COUNT`, `RETRY_DELAY`, `MIRROR_REFRESH`
- **Cleanup** — `CLEANUP_ENABLED`, `CLEANUP_ORPHANS`,
  `CLEANUP_FLATPAK_UNUSED`, `CLEANUP_PACCACHE`
- **Notifications** — `NOTIFICATIONS_ENABLED` and per-event toggles
- **Logging** — `LOG_DIR`, `LOG_FILE`, `LOG_ARCHIVE_COUNT`
- **Networking** — connectivity/DNS check hosts, `MIN_FREE_DISK_MB`

See the file itself for inline documentation of every option.

### `config/colors.conf`

Optional per-color overrides layered on top of the active theme, so you
can tweak a single accent color without forking a whole theme file.

### `config/keybindings.conf`

Remap any dashboard shortcut to a different key.

---

## Keyboard Shortcuts

| Key       | Action                                      |
|-----------|----------------------------------------------|
| `Q`       | Quit safely after the current package        |
| `Ctrl+C`  | Force quit immediately                        |
| `L`       | Toggle the live log panel                     |
| `P`       | Pause updates after the current package       |
| `R`       | Retry failed packages only                    |
| `C`       | Toggle the cleanup stage on/off               |
| `S`       | Show the update summary overlay               |
| `D`       | Show download statistics                      |
| `T`       | Switch themes                                  |
| `F`       | Toggle compact/full dashboard layout          |
| `E`       | Export a plain-text update report             |
| `H` / `?` | Show all keyboard shortcuts                   |

All bindings are remappable in `config/keybindings.conf`.

---

## How It Works

Arch Universal Updater cleanly separates **update logic** from **UI
rendering**:

1. `lib/pacman.sh`, `lib/yay.sh`, and `lib/flatpak.sh` each run their
   package manager as a background job, parsing its output line-by-line
   and writing structured progress into small `key=value` state files
   under `cache/state/` (via `lib/cache.sh`).
2. `lib/dashboard.sh` polls those state files on a timer
   (`REFRESH_RATE`) and redraws the fullscreen UI in place using the
   primitives in `lib/ui.sh` (cursor control, ANSI colors, Unicode
   box-drawing) and `lib/progress.sh` (progress bar rendering).
3. Keyboard input is read non-blockingly each frame and dispatched to
   actions (pause, retry, toggle panels, switch themes, export, quit).

Because the workers only ever talk through state files, the UI can be
redrawn as often as needed without touching update logic, and the update
logic has zero awareness of how (or whether) it's being displayed — the
same `pacman::run_updates` function powers both the dashboard and the
`--no-dashboard` plain-output mode.

Progress detection is necessarily heuristic: Pacman's line-based output is
parsed for known state transitions (downloading, verifying, installing,
running hooks) and `(x/y)` transaction counters; Yay/AUR builds are
tracked by build **stage** rather than byte progress, since `makepkg`
doesn't expose one; Flatpak's `\r`-redrawn progress bar is normalized into
line-based output and parsed for percentage and per-ref completion
markers. Output formats can vary across package manager versions — if a
parser misses a state on your setup, the live log panel (`L`) always shows
the raw underlying output.

---

## Architecture

```
arch-updater.sh   Entry point: arg parsing, preflight, orchestration
lib/utils.sh       Generic helpers (formatting, locale handling, atomics)
lib/parser.sh      Config/theme/keybinding loading
lib/logger.sh       File logging + log archival
lib/cache.sh        Runtime state store shared between workers and UI
lib/network.sh     Connectivity/DNS/disk-space preflight checks
lib/notifier.sh     notify-send wrapper
lib/mirror.sh       Optional reflector-based mirrorlist refresh
lib/retry.sh         Generic retry-with-backoff wrapper
lib/progress.sh     Progress bar rendering
lib/statistics.sh   CPU/RAM/network stats for the system panel
lib/pacman.sh        Pacman update checking + execution
lib/yay.sh            Yay/AUR update checking + execution
lib/flatpak.sh        Flatpak update checking + execution
lib/cleanup.sh        Orphans / unused Flatpaks / pacman cache trimming
lib/ui.sh              Low-level terminal primitives (boxes, colors, keys)
lib/dashboard.sh       Dashboard orchestration, event loop, rendering
```

---

## Folder Structure

```
arch-universal-updater/
├── arch-updater.sh
├── config/
│   ├── config.conf
│   ├── colors.conf
│   └── keybindings.conf
├── lib/
│   ├── dashboard.sh
│   ├── ui.sh
│   ├── parser.sh
│   ├── progress.sh
│   ├── pacman.sh
│   ├── yay.sh
│   ├── flatpak.sh
│   ├── cleanup.sh
│   ├── logger.sh
│   ├── retry.sh
│   ├── notifier.sh
│   ├── mirror.sh
│   ├── network.sh
│   ├── statistics.sh
│   ├── cache.sh
│   └── utils.sh
├── themes/
│   ├── default.theme
│   ├── nord.theme
│   ├── catppuccin.theme
│   └── dark.theme
├── logs/
├── cache/
├── screenshots/
├── README.md
└── LICENSE
```

---

## Contributing

Contributions are welcome. A few guidelines to keep the codebase
consistent:

1. **Keep UI and logic separate.** Anything that talks to pacman/yay/
   flatpak belongs in their respective `lib/*.sh` files and should only
   communicate with the dashboard through `lib/cache.sh` state files —
   never print directly to the screen from a worker.
2. **Guard against double-sourcing.** Every module starts with:
   ```bash
   [[ -n "${ARCH_UPDATER_<NAME>_LOADED:-}" ]] && return 0
   ARCH_UPDATER_<NAME>_LOADED=1
   ```
3. **Namespace functions** as `module::function_name` (e.g.
   `pacman::run_updates`), with a leading underscore for internal helpers
   (e.g. `dashboard::_draw_frame`).
4. **Run shellcheck** before submitting a PR:
   ```bash
   shellcheck arch-updater.sh lib/*.sh
   ```
5. **Test with mocked package managers** where possible — real
   pacman/yay/flatpak runs are hard to make reproducible in CI. Stub
   binaries that print representative output are the easiest way to
   exercise the parsers in `lib/pacman.sh`, `lib/yay.sh`, and
   `lib/flatpak.sh`.
6. **New themes** just need a `themes/<name>.theme` file defining the
   `COLOR_*` variables (see `themes/default.theme`) and an entry in the
   rotation list in `parser::next_theme`.

---

## Known Limitations

- Progress parsing is heuristic and based on common Pacman/Yay/Flatpak
  output patterns; unusual configurations or heavily localized output
  may fall back to stage-based progress instead of exact percentages.
- `P` (pause) is best-effort: it sends `SIGSTOP`/`SIGCONT` to the running
  worker process, so an operation already mid-flight (e.g. a single file
  download) may complete before the pause takes effect.
- Byte-level download speed/ETA fields are populated when the underlying
  package manager exposes them; otherwise they show as placeholders and
  the live log panel is the most accurate source of detail.

## License

Released under the [MIT License](LICENSE).
