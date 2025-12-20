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

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Detect the actual user (not root when using sudo)
if [ -n "$SUDO_USER" ]; then
    REAL_USER="$SUDO_USER"
    REAL_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
else
    REAL_USER="$USER"
    REAL_HOME="$HOME"
fi

CONFIG_DIR="$REAL_HOME/.config/pedalpusher"
STATE_DIR="$REAL_HOME/.local/state/pedalpusher"
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

        # Check for footswitch tool (AUR)
        if ! command -v footswitch &>/dev/null; then
            warn "footswitch tool not found. Install from AUR for hardware programming:"
            warn "  yay -S footswitch-git"
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
# Install Programs
# ------------------------------------------------------------------------------

install_programs() {
    info "Installing pedalpusher-filter to /usr/local/bin..."

    if [ -f "$SCRIPT_DIR/scripts/pedalpusher-filter" ]; then
        sudo cp "$SCRIPT_DIR/scripts/pedalpusher-filter" /usr/local/bin/
    else
        # Download from repo if not running from clone
        sudo curl -fsSL https://raw.githubusercontent.com/sigreer/pedalpusher/main/scripts/pedalpusher-filter \
            -o /usr/local/bin/pedalpusher-filter
    fi
    sudo chmod +x /usr/local/bin/pedalpusher-filter

    info "Installing pedalpusher-configure to /usr/local/bin..."

    if [ -f "$SCRIPT_DIR/scripts/pedalpusher-configure" ]; then
        sudo cp "$SCRIPT_DIR/scripts/pedalpusher-configure" /usr/local/bin/
    else
        sudo curl -fsSL https://raw.githubusercontent.com/sigreer/pedalpusher/main/scripts/pedalpusher-configure \
            -o /usr/local/bin/pedalpusher-configure
    fi
    sudo chmod +x /usr/local/bin/pedalpusher-configure
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
# See: https://github.com/sigreer/pedalpusher

# Hardware programming - what each physical switch sends
# Run `sudo pedalpusher-configure` to apply these settings
hardware:
  switch_1: F13    # Left pedal
  switch_2: F14    # Middle pedal
  switch_3: F15    # Right pedal

# Global settings
debounce: 0        # Default debounce in seconds
debug: false       # Log all key events

# Mappings - how each key is handled
mappings:
  pedal_left:
    key_code: 183       # F13
    script: pedal_a.sh
    "on": press
    passthrough: false

  pedal_middle:
    key_code: 184       # F14
    script: pedal_b.sh
    "on": press
    passthrough: false

  pedal_right:
    key_code: 185       # F15
    script: pedal_c.sh
    "on": press
    passthrough: false

scripts_dir: ~/.config/pedalpusher/scripts
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

echo "\$(date): Pedal ${pedal^^} pressed" >> ~/.local/state/pedalpusher/pedalpusher.log

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
- JOB: intercept -g \$DEVNODE | /usr/local/bin/pedalpusher-filter | uinput -d \$DEVNODE
  DEVICE:
    LINK: $device_link
UDEVMON_EOF
}

# ------------------------------------------------------------------------------
# Program Hardware
# ------------------------------------------------------------------------------

program_hardware() {
    if command -v footswitch &>/dev/null; then
        info "Programming foot switch hardware..."
        if sudo pedalpusher-configure 2>/dev/null; then
            info "Hardware programmed successfully!"
        else
            warn "Could not program hardware. Run manually: sudo pedalpusher-configure"
        fi
    else
        warn "footswitch tool not found - skipping hardware programming"
        warn "Install footswitch and run: sudo pedalpusher-configure"
    fi
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
    install_programs
    create_user_config
    install_udevmon_config
    program_hardware
    enable_service

    echo ""
    info "Installation complete!"
    echo ""
    echo "  Your config:  $CONFIG_DIR/config.yaml"
    echo "  Your scripts: $SCRIPTS_DIR/"
    echo "  Log file:     $STATE_DIR/pedalpusher.log"
    echo ""
    echo "  Commands:"
    echo "    sudo pedalpusher-configure      # Program hardware"
    echo "    sudo pedalpusher-configure -r   # Read hardware config"
    echo "    sudo systemctl restart udevmon  # Restart after config changes"
    echo ""
}

main "$@"
