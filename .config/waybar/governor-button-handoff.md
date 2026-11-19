# Waybar Governor Button — Handoff Document

## Files & Paths

| File | Purpose | Backup |
|------|---------|--------|
| `/home/rekcah/.config/waybar/config.jsonc` | Waybar module config | `config.jsonc.bak.<timestamp>` |
| `/home/rekcah/.local/share/arch/bin/cycle-governor.sh` | Click handler (cycles profiles) | `cycle-governor.sh.bak.<timestamp>` |
| `/home/rekcah/.local/share/arch/bin/cpu-governor-status.sh` | Status display (reads profile) | `cpu-governor-status.sh.bak.<timestamp>` |
| `/usr/local/bin/set-cpu-governor.sh` | **Obsolete** — no longer used | (keep for rollback) |

## Findings (with quoted evidence)

### Root Cause (CONFIRMED)
1. **Privilege failure**: Original `cycle-governor.sh` used `sudo -n /usr/local/bin/set-cpu-governor.sh` but no sudoers rule existed. Debug log showed: `sudo: a password is required` — script logged "switched to" but never actually changed anything.

2. **Fighting backend**: `power-profiles-daemon` (system service, active) owns CPU policy. It only exposes `balanced` and `power-saver` profiles. Direct `/sys` writes are reverted within seconds. Evidence:
   - `powerprofilesctl set power-saver` → governor becomes `schedutil`
   - `powerprofilesctl set balanced` → governor becomes `schedutil`
   - No `performance` profile available through daemon

### Ruled Out (with evidence)
- Click not received → Module in GTK tree, debug log shows no errors, script runs
- Module not in config → Listed in `modules-left`
- JSON syntax error → `waybar -l debug` parses successfully
- CSS blocking clicks → `#custom-cpu-governor` has normal margins
- Script not executable → All scripts have `+x`
- Wrong environment → Tested with `env -i` — same sudo failure
- TLP/auto-cpufreq fighting → Neither running (`systemctl` check)

### Real Power Backend
**power-profiles-daemon** (systemd: `power-profiles-daemon.service`, enabled, active)
- Profiles: `balanced` (default), `power-saver`
- Both map to `schedutil` governor on `acpi-cpufreq` driver
- Controls via D-Bus — **no root needed** for `powerprofilesctl`

## Changes Made

### 1. `cycle-governor.sh` — Complete rewrite
```bash
#!/bin/bash
# Cycle power-profiles-daemon profile: balanced <-> power-saver
# Supports "reverse" argument for on-click-right
set -u

CURRENT=$(powerprofilesctl get 2>/dev/null | awk '{print $1}' | sed 's/\*//')

if [[ "${1:-}" == "reverse" ]]; then
    case "$CURRENT" in
        balanced) NEXT="power-saver" ;;
        power-saver) NEXT="balanced" ;;
        *) NEXT="balanced" ;;
    esac
else
    case "$CURRENT" in
        balanced) NEXT="power-saver" ;;
        power-saver) NEXT="balanced" ;;
        *) NEXT="balanced" ;;
    esac
fi

if powerprofilesctl set "$NEXT" 2>/dev/null; then
    logger -t waybar-governor "Switched to $NEXT"
    pkill -RTMIN+1 waybar 2>/dev/null || true
else
    logger -t waybar-governor "Failed to switch to $NEXT"
    exit 1
fi
```

### 2. `cpu-governor-status.sh` — Complete rewrite
```bash
#!/bin/bash
# Show current power-profiles-daemon profile
set -u

PROFILE=$(powerprofilesctl get 2>/dev/null | awk '{print $1}' | sed 's/\*//')
GOVERNOR=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo "unknown")

case "$PROFILE" in
    balanced) ICON=$''; CLASS="performance" ;;  # lightning bolt
    power-saver) ICON=$''; CLASS="powersave" ;;  # battery
    *) ICON=$''; CLASS="unknown" ;;              # question mark
esac

printf '{"text":"%s", "tooltip":"Profile: %s\nGovernor: %s", "class":"%s"}\n' \
    "$ICON" "$PROFILE" "$GOVERNOR" "$CLASS"
```

### 3. `config.jsonc` — Module updates
```diff
"custom/cpu-governor": {
    "exec": "/home/rekcah/.local/share/arch/bin/cpu-governor-status.sh",
    "return-type": "json",
    "interval": 5,
    "tooltip": true,
    "format": "{}",
    "on-click": "/home/rekcah/.local/share/arch/bin/cycle-governor.sh",
+   "on-click-right": "/home/rekcah/.local/share/arch/bin/cycle-governor.sh reverse",
+   "signal": 1
  },
```

## Rollback Commands
```bash
# Restore all files
cp /home/rekcah/.config/waybar/config.jsonc.bak.* /home/rekcah/.config/waybar/config.jsonc
cp /home/rekcah/.local/share/arch/bin/cycle-governor.sh.bak.* /home/rekcah/.local/share/arch/bin/cycle-governor.sh
cp /home/rekcah/.local/share/arch/bin/cpu-governor-status.sh.bak.* /home/rekcah/.local/share/arch/bin/cpu-governor-status.sh
pkill -SIGUSR2 waybar  # Reload config
```

## Verification Results

| Test | Result | Evidence |
|------|--------|----------|
| `bash -n` both scripts | PASS | No syntax errors |
| Status script output | PASS | `{"text":"", "tooltip":"Profile: balanced\nGovernor: schedutil", "class":"performance"}` |
| Click cycle (balanced→power-saver) | PASS | `powerprofilesctl get` shows `power-saver`, status shows 🔋 icon |
| Click cycle (power-saver→balanced) | PASS | `powerprofilesctl get` shows `balanced`, status shows ⚡ icon |
| Reverse click (on-click-right) | PASS | `cycle-governor.sh reverse` toggles correctly |
| Minimal env test | PASS | `env -i HOME=$HOME PATH=/usr/bin:/bin bash cycle-governor.sh` works |
| Journal logging | PASS | `journalctl -t waybar-governor` shows "Switched to X" |
| Signal refresh (RTMIN+1) | PASS | Status updates within <1s after click |
| 30s persistence | PASS | Profile unchanged after 30s (`powerprofilesctl get` stable) |
| Waybar config reload | PASS | `pkill -SIGUSR2 waybar` works, module loads |

## Dead Ends / Attempts

| Attempt | Outcome |
|---------|---------|
| Direct `/sys` writes with sudo | Failed — no passwordless sudo, and daemon reverts anyway |
| `cpupower frequency-set` | Not installed; daemon would revert |
| TLP / auto-cpufreq | Not installed |
| Creating sudoers rule for `set-cpu-governor.sh` | Unnecessary — `powerprofilesctl` works without root |
| Polkit rule for graphical sudo | No polkit agent running (only `polkitd` daemon) |

## Open Questions (UNVERIFIED)

| Question | First Command to Investigate |
|----------|------------------------------|
| Can we get a true "performance" governor? | `systemctl mask power-profiles-daemon && cpupower frequency-set -g performance` (requires disabling daemon) |
| Does `power-profiles-daemon` support platform_profile on this hardware? | `cat /sys/firmware/acpi/platform_profile` (returns "No platform_profile") |
| Are there other power profiles via `powerprofilesctl list`? | Already checked — only balanced/power-saver |

## Resume Prompt (paste into fresh session)

> Continue from governor-button-handoff.md. The fix is implemented and verified. If you need to:
> - Add true performance mode: mask power-profiles-daemon, use cpupower with sudoers
> - Change icons: edit cpu-governor-status.sh ICON assignments
> - Adjust signal number: update config.jsonc "signal" and cycle-governor.sh pkill -RTMIN+N
> - Rollback: run the rollback commands in the handoff file

## CLAUDE.md Entry
```markdown
- [Governor Button Fix](governor-button-handoff.md) — Fixed Waybar CPU governor button to use power-profiles-daemon backend instead of broken sudo+sysfs approach. Cycles between balanced/power-saver profiles via powerprofilesctl (no root needed). Added signal-based instant refresh and right-click reverse cycle.
```