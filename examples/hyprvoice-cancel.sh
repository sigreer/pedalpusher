#!/bin/bash
# PedalPusher Example - Hyprvoice cancel operation with sound notification
# Cancels current hyprvoice operation and plays failure sound
#
# Dependencies: hyprvoice, pipewire (pw-play)
#
# Config example:
#   right:
#     key_code: 185
#     script: hyprvoice-cancel.sh
#     on: press
#     passthrough: false

# Determine user home (script runs as root via pedalpusher)
if [ -n "$PEDALPUSHER_USER" ]; then
    USER_HOME="/home/$PEDALPUSHER_USER"
elif [ -n "$SUDO_USER" ]; then
    USER_HOME="/home/$SUDO_USER"
elif [ "$(id -u)" -eq 0 ]; then
    # Fallback: find first non-root user with a home directory
    USER_HOME=$(getent passwd | awk -F: '$3 >= 1000 && $3 < 65534 {print $6; exit}')
else
    USER_HOME="$HOME"
fi
export HOME="$USER_HOME"

# Export user session environment (needed when running as root via pedalpusher)
ENV_FILE="$USER_HOME/.config/pedalpusher/env"
if [ -f "$ENV_FILE" ]; then
    set -a  # auto-export all variables
    source "$ENV_FILE"
    set +a
fi

LOG="$USER_HOME/.local/state/pedalpusher/pedalpusher.log"
SOUND_CANCEL="/usr/share/sounds/ocean/stereo/completion-fail.oga"
VOLUME_STATE_FILE="$USER_HOME/.local/state/pedalpusher/saved_volume"

# Ensure state directories exist
mkdir -p "$(dirname "$LOG")"

# Check current state using hyprvoice status
STATUS=$(hyprvoice status 2>&1)

echo "=== $(date) ===" >> "$LOG"
echo "RECEIVE: pedal event (PEDAL_EVENT=$PEDAL_EVENT)" >> "$LOG"
echo "STATE: $STATUS" >> "$LOG"

# Cancel hyprvoice operation
OUTPUT=$(hyprvoice cancel 2>&1)
EXIT_CODE=$?

# Play sound on successful cancellation
if [ $EXIT_CODE -eq 0 ]; then
    echo "ACTION: Cancelled operation" >> "$LOG"
    pw-play "$SOUND_CANCEL" 2>/dev/null &

    # Restore previous volume if saved (recording was in progress)
    if [ -f "$VOLUME_STATE_FILE" ]; then
        SAVED_VOLUME=$(cat "$VOLUME_STATE_FILE")
        wpctl set-volume @DEFAULT_AUDIO_SINK@ "$SAVED_VOLUME"
        echo "VOLUME: Restored to $SAVED_VOLUME" >> "$LOG"
        rm -f "$VOLUME_STATE_FILE"
    fi
else
    echo "ACTION: Cancel failed" >> "$LOG"
fi

echo "FEEDBACK: exit_code=$EXIT_CODE output='$OUTPUT'" >> "$LOG"
echo "" >> "$LOG"
