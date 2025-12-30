#!/bin/bash
# PedalPusher Example - Hyprvoice toggle with sound notifications
# Triggers on both press and release
# Reduces speaker volume during recording to avoid feedback
#
# Dependencies: hyprvoice, pipewire (pw-play, wpctl), bc
#
# Config example:
#   left:
#     key_code: 183
#     script: hyprvoice-toggle.sh
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
SOUND_START="/usr/share/sounds/ocean/stereo/completion-success.oga"
SOUND_STOP="/usr/share/sounds/ocean/stereo/completion-partial.oga"
VOLUME_STATE_FILE="$USER_HOME/.local/state/pedalpusher/saved_volume"
MAX_RECORDING_VOLUME=0.60  # 60% max volume during recording

# Ensure state directories exist
mkdir -p "$(dirname "$LOG")"
mkdir -p "$(dirname "$VOLUME_STATE_FILE")"

# Check current state using hyprvoice status
# States: idle, recording, transcribing
STATUS=$(hyprvoice status 2>&1)
if echo "$STATUS" | grep -qE "recording|transcribing"; then
    IS_RECORDING=true
else
    IS_RECORDING=false
fi

echo "=== $(date) ===" >> "$LOG"
echo "RECEIVE: pedal event (PEDAL_EVENT=$PEDAL_EVENT)" >> "$LOG"
echo "STATE: $STATUS (IS_RECORDING=$IS_RECORDING)" >> "$LOG"

# Toggle hyprvoice
OUTPUT=$(hyprvoice toggle 2>&1)
EXIT_CODE=$?

# Play sound and manage volume based on NEW state (opposite of what it was)
if [ "$IS_RECORDING" = true ]; then
    # Stopping recording - restore volume
    echo "ACTION: Stopping recording" >> "$LOG"
    pw-play "$SOUND_STOP" 2>/dev/null &

    # Restore previous volume if saved
    if [ -f "$VOLUME_STATE_FILE" ]; then
        SAVED_VOLUME=$(cat "$VOLUME_STATE_FILE")
        wpctl set-volume @DEFAULT_AUDIO_SINK@ "$SAVED_VOLUME"
        echo "VOLUME: Restored to $SAVED_VOLUME" >> "$LOG"
        rm -f "$VOLUME_STATE_FILE"
    fi
else
    # Starting recording - reduce volume
    echo "ACTION: Starting recording" >> "$LOG"

    # Save current volume
    CURRENT_VOLUME=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ | awk '{print $2}')
    echo "$CURRENT_VOLUME" > "$VOLUME_STATE_FILE"
    echo "VOLUME: Saved current volume $CURRENT_VOLUME" >> "$LOG"

    # Reduce volume if above threshold
    if (( $(echo "$CURRENT_VOLUME > $MAX_RECORDING_VOLUME" | bc -l) )); then
        wpctl set-volume @DEFAULT_AUDIO_SINK@ "$MAX_RECORDING_VOLUME"
        echo "VOLUME: Reduced to $MAX_RECORDING_VOLUME" >> "$LOG"
    else
        echo "VOLUME: Already at or below $MAX_RECORDING_VOLUME, no change" >> "$LOG"
    fi

    pw-play "$SOUND_START" 2>/dev/null &
fi

echo "FEEDBACK: exit_code=$EXIT_CODE output='$OUTPUT'" >> "$LOG"
echo "" >> "$LOG"
