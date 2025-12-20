# PedalPusher

USB foot pedal to script/key mapper for Linux, built on interception-tools.

## Architecture

```
USB Foot Switch (PCsensor FootSwitch)
         ↓
   /dev/input/event3 ← udevmon intercepts via LINK match
         ↓
   pedalpusher-filter (Python) ← reads config, triggers scripts, remaps keys
         ↓
      uinput → virtual keyboard device
         ↓
   Applications (Hyprland, etc.)
```

The system has three main components:
1. **pedalpusher** - Management utility (reload, status, log)
2. **pedalpusher-filter** - Intercepts key events, runs scripts, and remaps keys
3. **pedalpusher-configure** - Programs the USB foot switch hardware to send specific keycodes

## Key Files

### Repository
| File | Purpose |
|------|---------|
| `scripts/pedalpusher` | Management utility (reload, status, log) |
| `scripts/pedalpusher-filter` | Main event filter (Python, reads stdin events, writes stdout) |
| `scripts/pedalpusher-configure` | Hardware programming tool (Python, uses `footswitch` CLI) |
| `install.sh` | Installer script |
| `config.yaml.example` | Example configuration |

### Installed System Files
| File | Purpose |
|------|---------|
| `/usr/local/bin/pedalpusher` | Management utility |
| `/usr/local/bin/pedalpusher-filter` | Installed filter (accepts `--user` and `--config` args) |
| `/usr/local/bin/pedalpusher-configure` | Installed configure tool |
| `/etc/interception/udevmon.yaml` | udevmon job config - includes `--user` for explicit user |

### User Config (`~/.config/pedalpusher/`)
| File | Purpose |
|------|---------|
| `config.yaml` | User's pedal mappings and hardware config |
| `env` | Environment variables for GUI app scripts |
| `scripts/` | User's pedal scripts |

## Development

### Testing Changes

After modifying `scripts/pedalpusher-filter`:
```bash
sudo cp scripts/pedalpusher-filter /usr/local/bin/
sudo systemctl restart udevmon
sudo journalctl -u udevmon -f  # Watch logs
```

After modifying config only (no code changes):
```bash
sudo pedalpusher reload   # Sends SIGHUP, no restart needed
```

Enable debug mode in `~/.config/pedalpusher/config.yaml`:
```yaml
debug: true
```

### Event Format

pedalpusher-filter processes Linux input events (24 bytes):
```python
EVENT_FORMAT = 'llHHi'  # tv_sec, tv_usec, type, code, value
EV_KEY = 1
# value: 0=release, 1=press, 2=repeat
```

### Key Remapping

Remapping modifies the event's key code before passing through:
```python
output_data = struct.pack(EVENT_FORMAT, tv_sec, tv_usec, ev_type, remap_to, ev_value)
```

## Config Options

```yaml
mappings:
  pedal_name:
    key_code: 183       # Linux input event code to match
    script: script.sh   # Script to run (optional)
    remap_to: 28        # Output as different key code (optional)
    "on": press         # press, release, or both
    passthrough: false  # Pass key to system (true required for remap_to)
    debounce: 1.0       # Seconds between triggers
```

## User Detection

The filter runs as root under systemd but needs to know the user for:
- Finding config at `~/.config/pedalpusher/`
- Running scripts as that user (for GUI access)
- Loading the user's environment file

**Priority order for user detection:**
1. `--user` argument (set in udevmon.yaml by installer)
2. `--config` argument (explicit config path)
3. `PEDALPUSHER_USER` environment variable
4. `SUDO_USER` (for manual testing)
5. `loginctl` logged-in users
6. Scan `/home/*/` (fallback)

The installer writes `--user $USER` into udevmon.yaml, making detection explicit and reliable.

## Current Feature Status

### Working
- Hardware programming via `pedalpusher-configure`
- Script execution on press/release/both
- Key remapping (full keyboard support - F1-F24, letters, numbers, modifiers, media keys)
- Per-pedal debouncing
- Environment loading for GUI scripts
- Explicit user specification via `--user` flag (written to udevmon.yaml by installer)
- Hot reload via `sudo pedalpusher reload` (SIGHUP handler)

### Partially Implemented / Needs Work

1. **No hold/long-press detection** - Cannot trigger different actions for short press vs long hold. Would need to track press time and trigger on release based on duration.

2. **No chord/combo support** - Cannot detect multiple pedals pressed simultaneously to trigger a different action.

3. **No mouse button remapping** - Can only remap to keyboard keys, not mouse buttons (EV_KEY only, not EV_REL/EV_ABS).

4. **Scripts fire-and-forget** - Scripts run asynchronously with no way to know if they succeeded. Consider adding optional blocking mode or success callbacks.

5. **Single device only** - udevmon.yaml only matches one device. Would need multiple JOB entries for multiple foot pedals.

## Key Codes Reference

Common Linux input event codes:
```
F13=183, F14=184, F15=185, F16=186, F17=187, F18=188
ENTER=28, SPACE=57, TAB=15, ESCAPE=1
A=30, B=48, C=46, D=32, E=18, F=33
LEFT_CTRL=29, LEFT_SHIFT=42, LEFT_ALT=56
```

Full list: `/usr/include/linux/input-event-codes.h`

## Dependencies

- `interception-tools` - Core event interception (from distro repos)
- `python-yaml` / `pyyaml` - Config parsing
- `footswitch` (AUR: `footswitch-git`) - Hardware programming for PCsensor devices

## Commands

```bash
# Reload config without restart
sudo pedalpusher reload

# Check filter status and PID
pedalpusher status

# Tail logs
pedalpusher log

# Program hardware
sudo pedalpusher-configure

# Read hardware config
sudo pedalpusher-configure --read

# Check if hardware matches config
sudo pedalpusher-configure --check
```

## Debugging

```bash
# Check service status
sudo systemctl status udevmon

# Watch filter logs (or use: pedalpusher log)
sudo journalctl -u udevmon -f

# Test raw pedal events
sudo evtest /dev/input/by-id/usb-PCsensor_FootSwitch-event-kbd
```
