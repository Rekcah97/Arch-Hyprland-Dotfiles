#!/usr/bin/env python3
"""
Battery tooltip script for Waybar custom/battery module.

Reads battery energy from /sys/class/power_supply/BAT0/ and optionally
RAPL CPU package power from /sys/class/powercap/intel-rapl/.

Outputs JSON with text (formatted bar), class, percentage, and tooltip.
"""

import json
import os
import sys
import time
from pathlib import Path
from typing import Optional

# Configuration
BATTERY_PATH = Path("/sys/class/power_supply/BAT0")
RAPL_PKG_PATH = Path("/sys/class/powercap/intel-rapl/intel-rapl:0")
RAPL_CORE_PATH = Path("/sys/class/powercap/intel-rapl/intel-rapl:0/intel-rapl:0:0")

# State file location
RUNTIME_DIR = Path(os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}"))
STATE_FILE = RUNTIME_DIR / "waybar-battery-state.json"

# Sampling parameters
SAMPLE_INTERVAL = 2  # seconds between raw samples (script runs every 5s via Waybar)
WINDOW_SECONDS = 120  # sliding window for power calculation
MIN_DELTA_UWH = 300_000  # minimum energy delta to compute watts (µWh)
MAX_SAMPLES = WINDOW_SECONDS // SAMPLE_INTERVAL + 2  # ~62 samples for 120s window

# Battery icons (10% increments, matching original config.jsonc byte-for-byte)
ICONS_DISCHARGING = ["󰁺", "󰁻", "󰁼", "󰁽", "󰁾", "󰁿", "󰂀", "󰂁", "󰂂", "󰁹"]
ICONS_CHARGING = ["󰢜", "󰂆", "󰂇", "󰂈", "󰢝", "󰂉", "󰢞", "󰂊", "󰂋", "󰂅"]
ICON_FULL = "󰂅"


def read_int(path: Path) -> Optional[int]:
    """Read integer from file, return None on error."""
    try:
        return int(path.read_text().strip())
    except (OSError, ValueError):
        return None


def read_str(path: Path) -> Optional[str]:
    """Read string from file, return None on error."""
    try:
        return path.read_text().strip()
    except OSError:
        return None


def load_state() -> dict:
    """Load sampling state from file."""
    if STATE_FILE.exists():
        try:
            return json.loads(STATE_FILE.read_text())
        except (json.JSONDecodeError, OSError):
            pass
    return {"samples": [], "last_status": None}


def save_state(state: dict) -> None:
    """Save sampling state to file."""
    try:
        STATE_FILE.write_text(json.dumps(state))
    except OSError:
        pass


def get_icon(capacity: int, status: str) -> str:
    """Get battery icon based on capacity and status."""
    if status == "Full" or capacity >= 100:
        return ICON_FULL
    idx = min(capacity // 10, 9)
    if status == "Charging":
        return ICONS_CHARGING[idx]
    return ICONS_DISCHARGING[idx]


def get_class(capacity: int, status: str) -> str:
    """Get CSS class for Waybar styling."""
    if status == "Charging":
        return "charging"
    if status == "Full":
        return "full"
    if status in ("Not charging", "Plugged"):
        return "plugged"
    if capacity <= 10:
        return "critical"
    if capacity <= 20:
        return "warning"
    return "discharging"


def format_time(seconds: float) -> str:
    """Format seconds as 'Xh Ym' or 'Xm' (no '0h' prefix)."""
    if seconds < 0:
        return "Unknown"
    hours = int(seconds // 3600)
    minutes = int((seconds % 3600) // 60)
    if hours > 0:
        return f"{hours}h {minutes}m"
    return f"{minutes}m"


def escape_pango(text: str) -> str:
    """Escape text for Pango markup."""
    return text.replace("&", "&").replace("<", "<").replace(">", ">")


def compute_battery_watts(samples: list) -> Optional[float]:
    """
    Compute battery power in watts from sliding window of samples.
    Each sample: (timestamp, energy_now_µWh, status)
    Returns watts or None if insufficient data.
    """
    if len(samples) < 2:
        return None

    now = time.time()
    # Filter to window
    window_samples = [s for s in samples if now - s[0] <= WINDOW_SECONDS]
    if len(window_samples) < 2:
        return None

    oldest = window_samples[0]
    newest = window_samples[-1]

    # Must be same status (all discharging or all charging)
    if oldest[2] != newest[2]:
        return None

    dt = newest[0] - oldest[0]
    if dt < 10:  # Need at least 10 seconds of data
        return None

    delta_uwh = abs(newest[1] - oldest[1])
    if delta_uwh < MIN_DELTA_UWH:
        return None

    # Watts = µWh * 3600 / (dt_seconds * 1_000_000)
    watts = (delta_uwh * 3600) / (dt * 1_000_000)
    return watts


def compute_rapl_watts(path: Path, max_path: Path, prev_sample: Optional[tuple]) -> tuple[Optional[float], tuple]:
    """
    Compute RAPL power in watts from energy_uj delta.
    Returns (watts, (timestamp, energy_uj)) for next call.
    """
    energy_uj = read_int(path / "energy_uj")
    max_energy_uj = read_int(max_path)
    if energy_uj is None or max_energy_uj is None:
        return None, (time.time(), energy_uj) if energy_uj is not None else (time.time(), 0)

    now = time.time()
    if prev_sample is None:
        return None, (now, energy_uj)

    prev_time, prev_energy = prev_sample
    dt = now - prev_time
    if dt <= 0:
        return None, (now, energy_uj)

    delta = energy_uj - prev_energy
    if delta < 0:  # Wraparound
        delta += max_energy_uj

    watts = (delta * 1e-6) / dt
    return watts, (now, energy_uj)


def main() -> int:
    # Allow test mode with fake values via environment variables
    test_mode = os.environ.get("BATTERY_TEST_MODE") == "1"

    if test_mode:
        energy_now = int(os.environ.get("BATTERY_ENERGY_NOW", "0"))
        energy_full = int(os.environ.get("BATTERY_ENERGY_FULL", "41005000"))
        capacity = int(os.environ.get("BATTERY_CAPACITY", "50"))
        status = os.environ.get("BATTERY_STATUS", "Discharging")
    else:
        # Read battery data
        energy_now = read_int(BATTERY_PATH / "energy_now")
        energy_full = read_int(BATTERY_PATH / "energy_full")
        capacity = read_int(BATTERY_PATH / "capacity")
        status = read_str(BATTERY_PATH / "status")

    if energy_now is None or energy_full is None or capacity is None or status is None:
        # Minimal fallback output
        output = {
            "text": "󰂑 ?%",
            "percentage": 0,
            "class": "unknown",
            "tooltip": "<span>Battery unavailable</span>",
        }
        print(json.dumps(output))
        return 0

    # Load state
    state = load_state()
    samples = state.get("samples", [])
    last_status = state.get("last_status")

    # Clear history on status change
    if last_status is not None and last_status != status:
        samples = []

    # Add current sample (skip in test mode)
    if not test_mode:
        now = time.time()
        samples.append((now, energy_now, status))

        # Trim to max samples
        if len(samples) > MAX_SAMPLES:
            samples = samples[-MAX_SAMPLES:]

        # Update state
        state["samples"] = samples
        state["last_status"] = status
        save_state(state)

    # Compute battery watts (skip in test mode - return fixed values)
    if test_mode:
        # Return test values based on status
        if status == "Charging":
            battery_watts = 33.4
        elif status == "Discharging":
            battery_watts = 8.5
        else:
            battery_watts = None
    else:
        battery_watts = compute_battery_watts(samples)

    # Compute RAPL watts (optional, only if readable)
    rapl_pkg_watts = None
    rapl_core_watts = None

    # Try to read RAPL state from file
    rapl_state_file = RUNTIME_DIR / "waybar-rapl-state.json"
    rapl_pkg_prev = None
    rapl_core_prev = None
    if rapl_state_file.exists():
        try:
            rapl_state = json.loads(rapl_state_file.read_text())
            if "pkg" in rapl_state:
                rapl_pkg_prev = tuple(rapl_state["pkg"])
            if "core" in rapl_state:
                rapl_core_prev = tuple(rapl_state["core"])
        except (json.JSONDecodeError, OSError):
            pass

    # Compute package power
    if RAPL_PKG_PATH.exists():
        rapl_pkg_watts, rapl_pkg_prev = compute_rapl_watts(
            RAPL_PKG_PATH, RAPL_PKG_PATH / "max_energy_range_uj", rapl_pkg_prev
        )

    # Compute core power
    if RAPL_CORE_PATH.exists():
        rapl_core_watts, rapl_core_prev = compute_rapl_watts(
            RAPL_CORE_PATH, RAPL_CORE_PATH / "max_energy_range_uj", rapl_core_prev
        )

    # Save RAPL state
    try:
        rapl_state = {}
        if rapl_pkg_prev:
            rapl_state["pkg"] = rapl_pkg_prev
        if rapl_core_prev:
            rapl_state["core"] = rapl_core_prev
        rapl_state_file.write_text(json.dumps(rapl_state))
    except OSError:
        pass

    # Get icon and CSS class
    icon = get_icon(capacity, status)
    css_class = get_class(capacity, status)

    # Build bar text: "{capacity}% {icon}" (matching original native format)
    bar_text = f"{capacity}% {icon}"

    # Build tooltip lines
    tooltip_lines = []

    if status == "Discharging":
        if battery_watts is not None and battery_watts > 0:
            remaining_wh = energy_now / 1_000_000
            uptime_hours = remaining_wh / battery_watts
            uptime_seconds = uptime_hours * 3600
            tooltip_lines.append(f"Estimated uptime: {format_time(uptime_seconds)}")
            tooltip_lines.append(f"Power draw: {battery_watts:.1f} W")
        else:
            tooltip_lines.append("Calculating...")

    elif status == "Charging":
        if battery_watts is not None and battery_watts > 0:
            remaining_wh = (energy_full - energy_now) / 1_000_000
            charge_hours = remaining_wh / battery_watts
            charge_seconds = charge_hours * 3600
            tooltip_lines.append(f"Estimated charging time: {format_time(charge_seconds)}")
            tooltip_lines.append(f"Charging at: {battery_watts:.1f} W")
        else:
            tooltip_lines.append("Calculating...")

    elif status == "Full":
        tooltip_lines.append("Battery full")

    elif status in ("Not charging", "Plugged"):
        tooltip_lines.append("Plugged in, not charging")

    else:
        tooltip_lines.append(f"Status: {escape_pango(status)}")

    # Add optional RAPL line (CPU package only) - only if readable and > 0
    if rapl_pkg_watts is not None and rapl_pkg_watts > 0:
        tooltip_lines.append(f"CPU package: {rapl_pkg_watts:.1f} W")

    # Join with REAL newlines (not escaped), each line wrapped in <span> for Pango
    tooltip = "\n".join(f"<span>{escape_pango(line)}</span>" for line in tooltip_lines)

    output = {
        "text": bar_text,
        "percentage": capacity,
        "class": css_class,
        "tooltip": tooltip,
    }

    print(json.dumps(output))
    return 0


if __name__ == "__main__":
    sys.exit(main())