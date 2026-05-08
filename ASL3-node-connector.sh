#!/bin/bash
set -euo pipefail

#############################################
# ASL3 Node Connector Script
# By Goose - N8GMZ - 2025
# https://github.com/GooseThings/ASL3-node-connector/
#
# Patched: idle-detection fix (fail-safe to idle, not active)
#############################################

# --- CONFIGURABLE SETTINGS ---
NODE=64549                                       # This is your node that this script is installed on
TARGET=666380                                    # This is the node you want to automatically connect to
IDLE_LIMIT=180                                   # seconds of idle time on ASL node before disconnect
AUDIO_PATH="/var/lib/asterisk/sounds/custom"     # directory where the asterisk-owned WAV files are stored
EARLY_ANNOUNCE="WMEC-10min-proper"               # Put your early warning announcement here
EARLY_TIME=10                                    # The amount of time the early announcement will play before connecting (in seconds)
CONNECT_ANNOUNCE="WMEC-con-proper"               # connection announcement here (no .WAV or .ulaw at the end)
CONNECT_ANNOUNCE_TIME=20                         # how long the announcement is (in seconds).
                                                 # This is a dwell time so you connect after the announcement.
                                                 # If you shorten this to less than the announcement, then node will connect to the other node
                                                 # and you will hear the announcement on both nodes, which is bad.
DISCONNECT_ANNOUNCE="WMEC-discon-proper"         # announcement after disconnect
LOGFILE="/var/log/WMEC-connector.log"            # action log file
ASTERISK_BIN="/usr/sbin/asterisk"                # full path to asterisk binary (helps under cron)
# -----------------------------

DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
    echo "DRY RUN MODE ENABLED — No commands will be executed - Verbose output will commence"
fi

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" | tee -a "$LOGFILE"; }

run_asterisk_cmd() {
    if $DRY_RUN; then
        log "[DRY RUN] Would run: asterisk -rx \"$*\""
    else
        "$ASTERISK_BIN" -rx "$@"   # Requires the associated iLink macros (11, 14, 811, 814) in rpt.conf to be uncommented
    fi
}

play() {
    if $DRY_RUN; then
        log "[DRY RUN] Would play: $1"
    else
        "$ASTERISK_BIN" -rx "rpt playback $NODE $1"   # Requires asterisk to own the sound file
    fi
}

# get_keyed_status
#
# Sets globals RXKEYED and TXKEYED to "0" (idle), "1" (keyed), or "" (unknown).
# Returns 0 on a successful, parseable read; returns non-zero if the asterisk
# query failed or the keyed values could not be parsed. Callers MUST check the
# return value and treat a failure as "unknown" — never as "active" — otherwise
# transient CLI failures will continually reset the idle timer and the script
# will never disconnect.
get_keyed_status() {
    local output rc

    # Capture asterisk output without letting `set -e` abort the script if it fails.
    output=$("$ASTERISK_BIN" -rx "rpt show variables $NODE" 2>/dev/null) || rc=$?
    rc=${rc:-0}

    if (( rc != 0 )) || [[ -z "$output" ]]; then
        RXKEYED=""
        TXKEYED=""
        log "WARN: failed to read asterisk variables (rc=$rc, empty=$([[ -z "$output" ]] && echo yes || echo no))"
        return 1
    fi

    RXKEYED=$(echo "$output" | awk -F= '/RPT_RXKEYED/ {gsub(/^[ \t]+|[ \t\r\n]+$/, "", $2); print $2; exit}')
    TXKEYED=$(echo "$output" | awk -F= '/RPT_TXKEYED/ {gsub(/^[ \t]+|[ \t\r\n]+$/, "", $2); print $2; exit}')

    RXKEYED=$(echo "$RXKEYED" | tr -d '\r\n[:space:]')
    TXKEYED=$(echo "$TXKEYED" | tr -d '\r\n[:space:]')

    # If we got no value, treat as unknown (NOT active). Empty / non-0 / non-1
    # all collapse to "" so the caller can distinguish unknown from idle.
    [[ "$RXKEYED" == "0" || "$RXKEYED" == "1" ]] || RXKEYED=""
    [[ "$TXKEYED" == "0" || "$TXKEYED" == "1" ]] || TXKEYED=""

    log "Parsed RXKEYED='$RXKEYED', TXKEYED='$TXKEYED'"

    if [[ -z "$RXKEYED" || -z "$TXKEYED" ]]; then
        return 1
    fi
    return 0
}

# --- STEP 1: Wait for repeater to be idle before early announcement ---
# log "Waiting for repeater to be idle before early announcement..."
# start_wait=$(date +%s)
# while :; do
#     if ! get_keyed_status; then
#         log "Retrying due to parse error..."
#     elif [[ "$RXKEYED" == "0" && "$TXKEYED" == "0" ]]; then
#         log "Repeater idle. Playing early announcement."
#         play "$AUDIO_PATH/$EARLY_ANNOUNCE"
#         break
#     else
#         log "Repeater busy. Rechecking in 20s..."
#     fi
#
#     if (( $(date +%s) - start_wait > 120 )); then  # Force announcement after 2 minutes
#         log "Timeout waiting for idle before early announcement — forcing continue."
#         play "$AUDIO_PATH/$EARLY_ANNOUNCE"
#         break
#     fi
#     sleep 10
# done
# sleep "$EARLY_TIME"

# --- STEP 2: Wait for repeater to be idle before connection ---
log "Waiting for repeater to be idle before connect announcement..."
start_wait=$(date +%s)
while :; do
    if ! get_keyed_status; then
        log "Retrying due to parse error..."
    elif [[ "$RXKEYED" == "0" && "$TXKEYED" == "0" ]]; then
        # log "Repeater idle. Playing connect announcement."
        # play "$AUDIO_PATH/$CONNECT_ANNOUNCE"
        # sleep "$CONNECT_ANNOUNCE_TIME"
        log "Connecting to node $TARGET..."
        run_asterisk_cmd "rpt fun $NODE *3$TARGET"
        break
    else
        log "Repeater busy. Rechecking in 20s..."
    fi

    if (( $(date +%s) - start_wait > 120 )); then  # Force connection after 2 minutes
        log "Timeout waiting for idle before connect — forcing connection"
        # play "$AUDIO_PATH/$CONNECT_ANNOUNCE"
        # sleep "$CONNECT_ANNOUNCE_TIME"
        log "Forced connecting to node $TARGET..."
        run_asterisk_cmd "rpt fun $NODE *3$TARGET"
        break
    fi
    sleep 20
done

log "Successfully connected to node. Pausing for 5 minutes before monitoring for node being idle..."
sleep 300  # Let net settle. 5 minutes of buffer once connected in case the net starts late.

# --- STEP 3: Monitor for idle time ---
log "Monitoring for idle time (limit: $IDLE_LIMIT seconds)..."
LAST_ACTIVITY=$(date +%s)
CONSECUTIVE_PARSE_FAILURES=0
MAX_PARSE_FAILURES=20  # ~10 minutes at 30s sleep — bail out rather than hang forever

while :; do
    CURRENT_TIME=$(date +%s)

    if ! get_keyed_status; then
        # Could not determine state. Do NOT reset the timer (that was the old bug),
        # and do NOT count this poll as activity. Just skip and try again.
        CONSECUTIVE_PARSE_FAILURES=$(( CONSECUTIVE_PARSE_FAILURES + 1 ))
        log "WARN: keyed status unknown — skipping this poll (failure ${CONSECUTIVE_PARSE_FAILURES}/${MAX_PARSE_FAILURES})"

        if (( CONSECUTIVE_PARSE_FAILURES >= MAX_PARSE_FAILURES )); then
            log "ERROR: too many consecutive parse failures. Forcing disconnect from node $TARGET as a safety measure..."
            run_asterisk_cmd "rpt fun $NODE *1$TARGET"
            sleep 5
            # play "$AUDIO_PATH/$DISCONNECT_ANNOUNCE"
            log "Disconnected from node $TARGET (forced due to repeated parse failures)"
            exit 1
        fi
    else
        CONSECUTIVE_PARSE_FAILURES=0

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
            sleep 5
            # play "$AUDIO_PATH/$DISCONNECT_ANNOUNCE"
            log "Disconnected from node $TARGET"
            exit 0
        fi
    fi

    sleep 30  # Frequency (in seconds) at which to check whether the node is idle.
done
