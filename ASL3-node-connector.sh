#!/bin/bash
set -euo pipefail

#############################################
# ASL3 Node Connector Script
# By Goose - N8GMZ - 2025
# https://github.com/GooseThings/ASL3-node-connector/
#############################################

# --- CONFIGURABLE SETTINGS ---
NODE=64549
TARGET=29972
IDLE_LIMIT=60  # seconds
AUDIO_PATH="/var/lib/asterisk/sounds/custom/"

EARLY_ANNOUNCE="WMEC-10min-proper"
EARLY_TIME=480

CONNECT_ANNOUNCE="WMEC-con-proper"
CONNECT_ANNOUNCE_TIME=20

DISCONNECT_ANNOUNCE="WMEC-discon-proper"
LOGFILE="/var/log/ASL3-node-connector.log"
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
        asterisk -rx "$@"
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
    log "Repeater busy. Rechecking in 30s..."
    sleep 30
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
        run_asterisk_cmd "rpt fun $NODE *3$TARGET"
        break
    fi
    log "Repeater busy. Rechecking in 5s..."
    sleep 5
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
        run_asterisk_cmd "rpt fun $NODE *1$TARGET"
        sleep 3
        play "$AUDIO_PATH/$DISCONNECT_ANNOUNCE"
        log "Disconnected from node $TARGET. Exiting."
        exit 0
    fi

    sleep 30
done
