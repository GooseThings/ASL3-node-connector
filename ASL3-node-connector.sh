#!/bin/bash
set -euo pipefail

#############################################
# ASL3 Node Connector Script
# By Goose - N8GMZ - 2025
# https://github.com/GooseThings/ASL3-node-connector/
#############################################

# --- CONFIGURABLE SETTINGS ---
NODE=64549 # This is your node that this is installed on
TARGET=29972 # This is the node you want to automatically connect to
IDLE_LIMIT=60  # seconds of idle time on ASL node before disconnect
AUDIO_PATH="/var/lib/asterisk/sounds/custom" # directory where the WAV files are stored (recommended you put them here)

EARLY_ANNOUNCE="10-min-generic-announcement" # Put your 10 minute warning announcement here
EARLY_TIME=600 # The 10 minute announcement plays, and then it will wait this amount of time before connecting (in seconds)

CONNECT_ANNOUNCE="link-generic-announcement" # connection announcement here
CONNECT_ANNOUNCE_TIME=20 # how long the announcement is (in seconds).
   # This is a dwell time so you connect after the announcement
   # If you shorten this to less than the announcement, then node will connect to the other node
   # and you will hear the announcement on both nodes, which is bad.

DISCONNECT_ANNOUNCE="disconnect-generic-announcement" # announcement after disconnect
LOGFILE="/var/log/ASL3-node-connector.log" # action log file
# -----------------------------

DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
    echo "🛠️  DRY RUN MODE ENABLED — no commands will be executed"
fi

log() { echo "$(date '+%Y-%m-%d %H:%M:%S')  $*" | tee -a "$LOGFILE"; }

run_asterisk_cmd() {
    if $DRY_RUN; then
        log "[DRY RUN] Would run: asterisk -rx \"$*\""
    else
        /usr/sbin/asterisk -rx "$@"
    fi
}

play() {
    if $DRY_RUN; then
        log "[DRY RUN] Would play: $1"
    else
        /usr/sbin/asterisk -rx "rpt playback $NODE $1"
    fi
}

get_keyed_status() {
    local output
    output=$(asterisk -rx "rpt show variables $NODE")

    RXKEYED=$(echo "$output" | awk -F= '/RPT_RXKEYED/ {gsub(/^[ \t]+/, "", $2); print $2}')
    TXKEYED=$(echo "$output" | awk -F= '/RPT_TXKEYED/ {gsub(/^[ \t]+/, "", $2); print $2}')

    RXKEYED=$(echo "$RXKEYED" | tr -d '\r\n[:space:]')
    TXKEYED=$(echo "$TXKEYED" | tr -d '\r\n[:space:]')

    RXKEYED=${RXKEYED:-1}
    TXKEYED=${TXKEYED:-1}

    log "Parsed RXKEYED = '$RXKEYED', TXKEYED = '$TXKEYED'"
}

# --- STEP 1: Wait for repeater to be idle before early announcement ---
log "Waiting for repeater to be idle before early announcement..."
while :; do
    get_keyed_status
    if [[ "$RXKEYED" == "0" && "$TXKEYED" == "0" ]]; then
        log "Repeater idle. Playing early announcement."
        play "$AUDIO_PATH/$EARLY_ANNOUNCE"
        break
    fi
    log "Repeater busy. Rechecking in 20s..."
    sleep 20
done

sleep "$EARLY_TIME"

# --- STEP 2: Wait for repeater to be idle before connection ---
log "Waiting for repeater to be idle before connect announcement..."
while :; do
    get_keyed_status
    if [[ "$RXKEYED" == "0" && "$TXKEYED" == "0" ]]; then
        log "Repeater idle. Playing connect announcement."
        play "$AUDIO_PATH/$CONNECT_ANNOUNCE"
        sleep "$CONNECT_ANNOUNCE_TIME"
        log "Connecting to node $TARGET..."
        run_asterisk_cmd "rpt fun $NODE *813$TARGET"
        break
    fi
    log "Repeater busy. Rechecking in 10s..."
    sleep 10
done

sleep 300  # Let net settle

# --- STEP 3: Monitor for idle time ---
log "Monitoring for idle time (limit: $IDLE_LIMIT seconds)..."
LAST_ACTIVITY=$(date +%s)

while :; do
    get_keyed_status
    CURRENT_TIME=$(date +%s)

    if [[ "$RXKEYED" == "1" || "$TXKEYED" == "1" ]]; then
        LAST_ACTIVITY=$CURRENT_TIME
        log "Activity detected. Timer reset."
    else
        IDLE_TIME=$((CURRENT_TIME - LAST_ACTIVITY))
        log "Idle time: $IDLE_TIME seconds."
    fi

    if (( CURRENT_TIME - LAST_ACTIVITY >= IDLE_LIMIT )); then
        log "Idle time exceeded. Disconnecting from node $TARGET..."
        run_asterisk_cmd "rpt fun $NODE *811$TARGET"
        sleep 3
        play "$AUDIO_PATH/$DISCONNECT_ANNOUNCE"
        log "Disconnected from node $TARGET. Exiting."
        exit 0
    fi

    sleep 20
done
