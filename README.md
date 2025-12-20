# PedalPusher

Map USB foot pedal buttons to custom scripts and key remappings on Linux. Built on [interception-tools](https://gitlab.com/interception/linux/tools).

## Features

- **Hardware programming** - Configure what keys each pedal sends
- **Script triggers** - Run custom scripts on pedal press/release
- **Key remapping** - Transform pedal keys to different outputs
- **Debouncing** - Prevent rapid-fire triggers from sensitive pedals
- **Per-pedal configuration** - Different behavior for each pedal

## Quick Install

```bash
git clone https://github.com/sigreer/pedalpusher.git
cd pedalpusher && ./install.sh
```

## What It Does

1. Programs your USB foot switch to send unique keys (F13-F15)
2. Intercepts those keys before they reach applications
3. Runs your scripts and/or remaps keys based on configuration
4. Passes through (or suppresses) keys as configured

## Configuration

### Hardware Programming: `~/.config/pedalpusher/config.yaml`

```yaml
# What each physical switch sends
hardware:
  switch_1: F13    # Left pedal
  switch_2: F14    # Middle pedal
  switch_3: F15    # Right pedal
```

Apply with: `sudo pedalpusher-configure`

### Mappings: `~/.config/pedalpusher/config.yaml`

```yaml
mappings:
  pedal_left:
    key_code: 183       # F13
    script: my-script.sh
    "on": both          # press, release, or both
    passthrough: false  # suppress the key
    debounce: 1.0       # prevent rapid triggers

  pedal_middle:
    key_code: 184       # F14
    remap_to: 183       # output as F13 instead
    "on": press
    passthrough: true   # pass the remapped key through

  pedal_right:
    key_code: 185       # F15
    remap_to: 28        # output as Enter
    "on": press
    passthrough: true
```

### User Scripts: `~/.config/pedalpusher/scripts/`

```bash
#!/bin/bash
# Example: Toggle voice dictation
hyprvoice toggle

# Example: Send notification
notify-send "Pedal pressed!"

# Example: Simulate keypress
xdotool key ctrl+shift+m
```

### Environment Variables: `~/.config/pedalpusher/env`

For GUI apps (notify-send, xdotool, etc.):

```
DISPLAY=:0
XDG_RUNTIME_DIR=/run/user/1000
DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus
```

## File Locations

| Path | Purpose |
|------|---------|
| `/etc/interception/udevmon.yaml` | System config - device matching |
| `/usr/local/bin/pedalpusher-filter` | Event filter program |
| `/usr/local/bin/pedalpusher-configure` | Hardware programming tool |
| `~/.config/pedalpusher/config.yaml` | Your mappings and hardware config |
| `~/.config/pedalpusher/scripts/` | Your scripts |
| `~/.config/pedalpusher/env` | Environment for GUI apps |
| `~/.local/state/pedalpusher/` | Log files |

## Commands

```bash
# Program foot switch hardware from config
sudo pedalpusher-configure

# Read current hardware configuration
sudo pedalpusher-configure --read

# Check if hardware matches config
sudo pedalpusher-configure --check

# Restart after config changes
sudo systemctl restart udevmon

# View logs
sudo journalctl -u udevmon -f
tail -f ~/.local/state/pedalpusher/pedalpusher.log
```

## Finding Your Device

```bash
# List input devices
ls -la /dev/input/by-id/

# Test which events your pedals generate
sudo evtest /dev/input/by-id/usb-YourDevice-event-kbd
```

## Key Codes Reference

| Key | Code | Key | Code |
|-----|------|-----|------|
| F13 | 183 | Enter | 28 |
| F14 | 184 | A | 30 |
| F15 | 185 | B | 48 |
| F16 | 186 | C | 46 |

## Troubleshooting

### Check service status
```bash
sudo systemctl status udevmon
```

### Pedals not responding?
1. Verify hardware config: `sudo pedalpusher-configure --read`
2. Check device path in `/etc/interception/udevmon.yaml`
3. Ensure service is running: `sudo systemctl status udevmon`
4. Enable debug in config and check logs

### PCsensor FootSwitch quirks
- Must program all switches in a single command
- The `pedalpusher-configure` script handles this automatically

## Uninstall

```bash
sudo systemctl stop udevmon
sudo systemctl disable udevmon
sudo rm /usr/local/bin/pedalpusher-filter
sudo rm /usr/local/bin/pedalpusher-configure
sudo rm /etc/interception/udevmon.yaml
rm -rf ~/.config/pedalpusher
```

## How It Works

```
USB Foot Switch
      ↓
  [event3] ← intercept grabs device
      ↓
pedalpusher-filter
  ├── Triggers scripts for mapped keys
  ├── Remaps keys (F14→F13, etc.)
  └── Suppresses or passes through
      ↓
   [uinput] → Virtual device
      ↓
Applications (Hyprland, etc.)
```

## License

MIT
