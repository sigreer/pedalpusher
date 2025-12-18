# PedalPusher

Map USB foot pedal buttons to custom scripts on Linux. Built on [interception-tools](https://gitlab.com/interception/linux/tools).

## Quick Install

```bash
curl -fsSL https://raw.githubusercontent.com/sigreer/pedalpusher/main/install.sh | bash
```

Or clone and run:

```bash
git clone https://github.com/sigreer/pedalpusher.git
cd pedalpusher && ./install.sh
```

## What It Does

- Intercepts key events from your USB foot pedal (typically mapped as `a`, `b`, `c`)
- Runs your custom scripts when pedals are pressed
- Suppresses the original key events (no more random letters appearing)
- Runs scripts as your user, not root

## Configuration

### User Config: `~/.config/footpedal/config.yaml`

```yaml
mappings:
  pedal_a:
    key_code: 30        # KEY_A (left pedal)
    script: pedal_a.sh  # Script in scripts_dir
    on: press           # press, release, or both
    passthrough: false  # true to also send original key

  pedal_b:
    key_code: 48        # KEY_B (middle pedal)
    script: pedal_b.sh
    on: press
    passthrough: false

  pedal_c:
    key_code: 46        # KEY_C (right pedal)
    script: pedal_c.sh
    on: press
    passthrough: false

scripts_dir: ~/.config/footpedal/scripts
```

### User Scripts: `~/.config/footpedal/scripts/`

Edit the scripts to do whatever you need:

```bash
# Example: pedal_a.sh - Toggle voice dictation
#!/bin/bash
numen toggle

# Example: pedal_b.sh - Push-to-talk
#!/bin/bash
xdotool key ctrl+shift+m

# Example: pedal_c.sh - Send notification
#!/bin/bash
notify-send "Pedal C pressed!"
```

### Environment Variables: `~/.config/footpedal/env`

For GUI apps (notify-send, xdotool, etc.), set your display variables:

```
DISPLAY=:0
XDG_RUNTIME_DIR=/run/user/1000
DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus
```

## File Locations

| Path | Purpose |
|------|---------|
| `/etc/interception/udevmon.yaml` | System config - device matching |
| `/usr/local/bin/footpedal-filter` | Filter program |
| `~/.config/footpedal/config.yaml` | Your key mappings |
| `~/.config/footpedal/scripts/` | Your scripts |
| `~/.config/footpedal/env` | Environment for GUI apps |
| `~/.local/state/footpedal/` | Log files |

## Finding Your Device

```bash
# List input devices
ls -la /dev/input/by-id/

# Test which events your pedals generate
sudo evtest /dev/input/by-id/usb-YourDevice-event-kbd
```

Common key codes:
- `KEY_A` = 30
- `KEY_B` = 48
- `KEY_C` = 46

## Troubleshooting

### Check service status
```bash
sudo systemctl status udevmon
```

### View logs
```bash
# Service logs
sudo journalctl -u udevmon -f

# Script output
tail -f ~/.local/state/footpedal/footpedal.log
```

### Restart after config changes
```bash
sudo systemctl restart udevmon
```

### Pedals still typing letters?

1. Verify device path in `/etc/interception/udevmon.yaml`
2. Check service is running: `sudo systemctl status udevmon`
3. Look for errors: `sudo journalctl -u udevmon`

## Uninstall

```bash
sudo systemctl stop udevmon
sudo systemctl disable udevmon
sudo rm /usr/local/bin/footpedal-filter
sudo rm /etc/interception/udevmon.yaml
rm -rf ~/.config/footpedal
```

## How It Works

1. `udevmon` watches for the foot pedal device
2. `intercept` captures raw input events from the device
3. `footpedal-filter` reads events, triggers scripts, and decides what to pass through
4. `uinput` creates a virtual device for any passed-through events

## License

MIT
