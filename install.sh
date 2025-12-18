#!/bin/bash
#
# PedalPusher - USB Foot Pedal to Script Mapper
# https://github.com/sigreer/pedalpusher
#
# Install with:
#   curl -fsSL https://raw.githubusercontent.com/sigreer/pedalpusher/main/install.sh | bash
#
# Or clone and run:
#   git clone https://github.com/sigreer/pedalpusher.git
#   cd pedalpusher && ./install.sh
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# Detect the actual user (not root when using sudo)
if [ -n "$SUDO_USER" ]; then
    REAL_USER="$SUDO_USER"
    REAL_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
else
    REAL_USER="$USER"
    REAL_HOME="$HOME"
fi

CONFIG_DIR="$REAL_HOME/.config/footpedal"
STATE_DIR="$REAL_HOME/.local/state/footpedal"
SCRIPTS_DIR="$CONFIG_DIR/scripts"

# ------------------------------------------------------------------------------
# Dependency Installation
# ------------------------------------------------------------------------------

install_dependencies() {
    info "Checking dependencies..."

    if command -v pacman &> /dev/null; then
        # Arch Linux
        local pkgs=()
        ! pacman -Qi interception-tools &>/dev/null && pkgs+=(interception-tools)
        ! pacman -Qi python-yaml &>/dev/null && pkgs+=(python-yaml)

        if [ ${#pkgs[@]} -gt 0 ]; then
            info "Installing packages: ${pkgs[*]}"
            sudo pacman -S --noconfirm "${pkgs[@]}"
        fi
    elif command -v apt-get &> /dev/null; then
        # Debian/Ubuntu
        local pkgs=()
        ! dpkg -l interception-tools &>/dev/null 2>&1 && pkgs+=(interception-tools)
        ! python3 -c "import yaml" &>/dev/null 2>&1 && pkgs+=(python3-yaml)

        if [ ${#pkgs[@]} -gt 0 ]; then
            info "Installing packages: ${pkgs[*]}"
            sudo apt-get update
            sudo apt-get install -y "${pkgs[@]}"
        fi
    elif command -v dnf &> /dev/null; then
        # Fedora
        local pkgs=()
        ! rpm -q interception-tools &>/dev/null 2>&1 && pkgs+=(interception-tools)
        ! python3 -c "import yaml" &>/dev/null 2>&1 && pkgs+=(python3-pyyaml)

        if [ ${#pkgs[@]} -gt 0 ]; then
            info "Installing packages: ${pkgs[*]}"
            sudo dnf install -y "${pkgs[@]}"
        fi
    else
        warn "Unknown package manager. Please install manually:"
        warn "  - interception-tools"
        warn "  - python-yaml (PyYAML)"
    fi
}

# ------------------------------------------------------------------------------
# Create Filter Program
# ------------------------------------------------------------------------------

install_filter() {
    info "Installing footpedal-filter to /usr/local/bin..."

    sudo tee /usr/local/bin/footpedal-filter > /dev/null << 'FILTER_EOF'
#!/usr/bin/env python3
"""
Foot pedal filter for intercept-tools.
Reads input events, triggers user scripts for mapped keys, and passes through others.
"""

import os
import sys
import struct
import subprocess
import yaml
from pathlib import Path

EVENT_SIZE = 24
EVENT_FORMAT = 'llHHi'
EV_KEY = 1
KEY_RELEASE, KEY_PRESS, KEY_REPEAT = 0, 1, 2

def get_user_config_path():
    user = os.environ.get('SUDO_USER') or os.environ.get('USER')
    if os.getuid() == 0:
        try:
            result = subprocess.run(
                ['loginctl', 'list-users', '--no-legend'],
                capture_output=True, text=True, timeout=5
            )
            for line in result.stdout.strip().split('\n'):
                if line.strip():
                    parts = line.split()
                    if len(parts) >= 2:
                        user = parts[1]
                        break
        except Exception:
            pass
    if user and user != 'root':
        return Path(f'/home/{user}/.config/footpedal')
    return Path.home() / '.config' / 'footpedal'

def load_config():
    config_dir = get_user_config_path()
    config_file = config_dir / 'config.yaml'
    default_config = {
        'mappings': {
            'pedal_a': {'key_code': 30, 'script': 'pedal_a.sh', 'on': 'press', 'passthrough': False},
            'pedal_b': {'key_code': 48, 'script': 'pedal_b.sh', 'on': 'press', 'passthrough': False},
            'pedal_c': {'key_code': 46, 'script': 'pedal_c.sh', 'on': 'press', 'passthrough': False},
        },
        'scripts_dir': str(config_dir / 'scripts'),
        'user': None,
    }
    if config_file.exists():
        try:
            with open(config_file) as f:
                user_config = yaml.safe_load(f) or {}
                for key, value in user_config.items():
                    if key == 'mappings' and isinstance(value, dict):
                        default_config['mappings'].update(value)
                    else:
                        default_config[key] = value
        except Exception as e:
            sys.stderr.write(f"footpedal-filter: Error loading config: {e}\n")
    return default_config

def run_script(script_path, user=None):
    if not os.path.exists(script_path):
        sys.stderr.write(f"footpedal-filter: Script not found: {script_path}\n")
        return
    try:
        env = os.environ.copy()
        if user:
            env['HOME'] = f'/home/{user}'
            env['USER'] = user
            env['LOGNAME'] = user
            try:
                with open(f'/home/{user}/.config/footpedal/env', 'r') as f:
                    for line in f:
                        if '=' in line:
                            k, v = line.strip().split('=', 1)
                            env[k] = v
            except FileNotFoundError:
                pass
        if os.getuid() == 0 and user and user != 'root':
            cmd = ['sudo', '-u', user, '-E', script_path]
        else:
            cmd = [script_path]
        subprocess.Popen(cmd, env=env, stdout=subprocess.DEVNULL,
                        stderr=subprocess.DEVNULL, start_new_session=True)
    except Exception as e:
        sys.stderr.write(f"footpedal-filter: Error running script: {e}\n")

def main():
    config = load_config()
    scripts_dir = Path(config['scripts_dir'])
    key_mappings = {}
    for name, mapping in config['mappings'].items():
        key_code = mapping.get('key_code')
        if key_code is not None:
            key_mappings[key_code] = mapping
    user = config.get('user')
    if not user:
        config_dir = get_user_config_path()
        parts = config_dir.parts
        if len(parts) >= 3 and parts[1] == 'home':
            user = parts[2]
    stdin, stdout = sys.stdin.buffer, sys.stdout.buffer
    while True:
        data = stdin.read(EVENT_SIZE)
        if not data or len(data) < EVENT_SIZE:
            break
        tv_sec, tv_usec, ev_type, ev_code, ev_value = struct.unpack(EVENT_FORMAT, data)
        should_passthrough = True
        if ev_type == EV_KEY and ev_code in key_mappings:
            mapping = key_mappings[ev_code]
            trigger_on = mapping.get('on', 'press')
            trigger = False
            if trigger_on == 'press' and ev_value == KEY_PRESS:
                trigger = True
            elif trigger_on == 'release' and ev_value == KEY_RELEASE:
                trigger = True
            elif trigger_on == 'both' and ev_value in (KEY_PRESS, KEY_RELEASE):
                trigger = True
            if trigger:
                script_name = mapping.get('script', '')
                if script_name:
                    run_script(str(scripts_dir / script_name), user)
            should_passthrough = mapping.get('passthrough', False)
        if should_passthrough:
            stdout.write(data)
            stdout.flush()

if __name__ == '__main__':
    main()
FILTER_EOF

    sudo chmod +x /usr/local/bin/footpedal-filter
}

# ------------------------------------------------------------------------------
# Create User Configuration
# ------------------------------------------------------------------------------

create_user_config() {
    info "Creating user configuration in $CONFIG_DIR..."

    mkdir -p "$CONFIG_DIR" "$SCRIPTS_DIR" "$STATE_DIR"

    # Main config file
    if [ ! -f "$CONFIG_DIR/config.yaml" ]; then
        cat > "$CONFIG_DIR/config.yaml" << 'CONFIG_EOF'
# PedalPusher Configuration
# Key codes: KEY_A=30, KEY_B=48, KEY_C=46

mappings:
  pedal_a:
    key_code: 30        # KEY_A (left pedal)
    script: pedal_a.sh
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
CONFIG_EOF
    fi

    # Environment file for GUI apps
    cat > "$CONFIG_DIR/env" << ENV_EOF
DISPLAY=:0
XDG_RUNTIME_DIR=/run/user/$(id -u "$REAL_USER")
DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u "$REAL_USER")/bus
ENV_EOF

    # Default scripts
    for pedal in a b c; do
        script="$SCRIPTS_DIR/pedal_${pedal}.sh"
        if [ ! -f "$script" ]; then
            cat > "$script" << SCRIPT_EOF
#!/bin/bash
# Pedal ${pedal^^} script - customize this!

echo "\$(date): Pedal ${pedal^^} pressed" >> ~/.local/state/footpedal/footpedal.log

# Examples:
# notify-send "Pedal ${pedal^^}"
# xdotool key ctrl+shift+${pedal}
SCRIPT_EOF
            chmod +x "$script"
        fi
    done

    # Fix ownership if running as root
    if [ "$(id -u)" -eq 0 ]; then
        chown -R "$REAL_USER:$REAL_USER" "$CONFIG_DIR" "$STATE_DIR"
    fi
}

# ------------------------------------------------------------------------------
# Create udevmon Configuration
# ------------------------------------------------------------------------------

install_udevmon_config() {
    info "Installing udevmon configuration..."

    # Find foot pedal device
    local device_link=""
    for link in /dev/input/by-id/*FootSwitch*-event-kbd /dev/input/by-id/*foot*-event-kbd /dev/input/by-id/*pedal*-event-kbd; do
        if [ -e "$link" ]; then
            device_link="$link"
            break
        fi
    done

    if [ -z "$device_link" ]; then
        warn "No foot pedal device found automatically."
        warn "Please edit /etc/interception/udevmon.yaml with your device path."
        warn "Find it with: ls -la /dev/input/by-id/"
        device_link="/dev/input/by-id/usb-YOUR_DEVICE-event-kbd"
    else
        info "Found foot pedal: $device_link"
    fi

    sudo mkdir -p /etc/interception
    sudo tee /etc/interception/udevmon.yaml > /dev/null << UDEVMON_EOF
# PedalPusher - Foot pedal interception config
- JOB: intercept -g \$DEVNODE | /usr/local/bin/footpedal-filter | uinput -d \$DEVNODE
  DEVICE:
    LINK: $device_link
UDEVMON_EOF
}

# ------------------------------------------------------------------------------
# Enable Service
# ------------------------------------------------------------------------------

enable_service() {
    info "Enabling udevmon service..."
    sudo systemctl enable udevmon
    sudo systemctl restart udevmon

    if sudo systemctl is-active --quiet udevmon; then
        info "Service is running!"
    else
        error "Service failed to start. Check: sudo journalctl -u udevmon"
    fi
}

# ------------------------------------------------------------------------------
# Main
# ------------------------------------------------------------------------------

main() {
    echo ""
    echo "  ╔═══════════════════════════════════════╗"
    echo "  ║        PedalPusher Installer          ║"
    echo "  ║   USB Foot Pedal → Script Mapper      ║"
    echo "  ╚═══════════════════════════════════════╝"
    echo ""

    # Check if running with appropriate privileges
    if [ "$(id -u)" -ne 0 ]; then
        info "Re-running with sudo..."
        exec sudo -E bash "$0" "$@"
    fi

    install_dependencies
    install_filter
    create_user_config
    install_udevmon_config
    enable_service

    echo ""
    info "Installation complete!"
    echo ""
    echo "  Your config:  $CONFIG_DIR/config.yaml"
    echo "  Your scripts: $SCRIPTS_DIR/"
    echo "  Log file:     $STATE_DIR/footpedal.log"
    echo ""
    echo "  Test with:    tail -f $STATE_DIR/footpedal.log"
    echo ""
}

main "$@"
