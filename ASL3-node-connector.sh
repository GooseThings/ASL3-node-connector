#!/bin/bash

#############################################
# ASL3 Node Connector (ASLNC)
# By Goose - N8GMZ - 2025
# https://github.com/GooseThings/ASL3-node-connector/
#
# Automatically connects your ASL3 node to a target node
# at a scheduled time, monitors for inactivity, and
# disconnects when the net goes idle.
#############################################

# --- CONFIGURABLE SETTINGS ---

NODE=64549                              # Your local ASL3 node number
TARGET=666380                           # The node you want to connect to
IDLE_LIMIT=180                          # Seconds of idle time before auto-disconnect
AUDIO_PATH="/var/lib/asterisk/sounds/custom"  # Directory containing your WAV announcement files

EARLY_ANNOUNCE="WMEC-10min-proper"      # Filename of early warning announcement (no extension)
EARLY_TIME=10                           # Seconds before connecting to play early announcement

CONNECT_ANNOUNCE="WMEC-con-proper"      # Filename of connection announcement (no extension)
CONNECT_ANNOUNCE_TIME=20                # Seconds to wait after playing connection announcement
                                        # before actually connecting. Must be >= announcement length.

DISCONNECT_ANNOUNCE="WMEC-discon-proper" # Filename of disconnection announcement (no extension)

LOGFILE="/var/log/ASL3-node-connector.log"  # Log file path

# How long to wait after connecting before starting idle monitoring.
# Gives the net time to get underway before the idle timer kicks in.
NET_SETTLE_TIME=300                     # seconds (default: 5 minutes)

# How frequently to poll the node status during idle monitoring.
IDLE_POLL_INTERVAL=30                   # seconds

# How long to wait for the repeater to go idle before forcing a connect or announcement.
IDLE_WAIT_TIMEOUT=120                   # seconds

# -----------------------------

ASTERISK_BIN="/usr/sbin/asterisk"

# --- DRY RUN SUPPORT ---
DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
    echo "DRY RUN MODE ENABLED -- No commands will be executed. Verbose output follows."
fi

# --- LOGGING ---
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $*" | tee -a "$LOGFILE"
}

# --- PRE-FLIGHT CHECKS ---
preflight_check() {
    local errors=0

    if [[ ! -x "$ASTERISK_BIN" ]]; then
        log "ERROR: Asterisk binary not found or not executable at $ASTERISK_BIN"
        errors=$((errors + 1))
    fi

    if [[ ! -w "$(dirname "$LOGFILE")" ]]; then
        log "ERROR: Cannot write to log directory $(dirname "$LOGFILE"). Check permissions."
        errors=$((errors + 1))
    fi

    if [[ -z "$NODE" || -z "$TARGET" ]]; then
        log "ERROR: NODE and TARGET must both be set in the configuration section."
        errors=$((errors + 1))
    fi

    if [[ "$NODE" == "$TARGET" ]]; then
        log "ERROR: NODE and TARGET cannot be the same node number."
        errors=$((errors + 1))
    fi

    if [[ $errors -gt 0 ]]; then
        log "Pre-flight check failed with $errors error(s). Aborting."
        exit 1
    fi

    log "Pre-flight checks passed."
}

# --- ASTERISK COMMAND WRAPPER ---
run_asterisk_cmd() {
    if $DRY_RUN; then
        log "[DRY RUN] Would run: $ASTERISK_BIN -rx \"$*\""
        return 0
    fi

    local output
    local exit_code

    # Note: rpt fun commands (e.g. *3, *1 with iLink) require the corresponding
    # entries in rpt.conf to be uncommented. See README for details.
    output=$("$ASTERISK_BIN" -rx "$@" 2>&1)
    exit_code=$?

    if [[ $exit_code -ne 0 ]]; then
        log "WARNING: Asterisk command returned exit code $exit_code. Output: $output"
    else
        log "Asterisk command succeeded. Output: $output"
    fi

    return $exit_code
}

# --- AUDIO PLAYBACK ---
play() {
    local sound_file="$1"
    if $DRY_RUN; then
        log "[DRY RUN] Would play: $sound_file"
        return 0
    fi

    if [[ -z "$sound_file" ]]; then
        log "No sound file specified, skipping playback."
        return 0
    fi

    local full_path="$AUDIO_PATH/$sound_file"

    if [[ ! -f "$full_path.wav" && ! -f "$full_path.ulaw" && ! -f "$full_path" ]]; then
        log "WARNING: Sound file not found at $full_path (.wav or .ulaw). Skipping playback."
        return 1
    fi

    # Note: asterisk must have ownership of the sound file for playback to work.
    # Run: chown -R asterisk:asterisk $AUDIO_PATH
    "$ASTERISK_BIN" -rx "rpt playback $NODE $full_path"
}

# --- NODE STATUS ---
get_keyed_status() {
    local output
    local exit_code

    if $DRY_RUN; then
        RXKEYED=0
        TXKEYED=0
        return 0
    fi

    output=$("$ASTERISK_BIN" -rx "rpt show variables $NODE" 2>&1)
    exit_code=$?

    if [[ $exit_code -ne 0 ]]; then
        log "WARNING: Could not retrieve node variables (exit code $exit_code). Assuming busy."
        RXKEYED=1
        TXKEYED=1
        return 1
    fi

    RXKEYED=$(echo "$output" | awk -F= '/RPT_RXKEYED/ {gsub(/^[ \t]+/, "", $2); print $2}' | tr -d '\r\n[:space:]')
    TXKEYED=$(echo "$output" | awk -F= '/RPT_TXKEYED/ {gsub(/^[ \t]+/, "", $2); print $2}' | tr -d '\r\n[:space:]')

    # Default to busy (1) if we could not parse the values
    RXKEYED=${RXKEYED:-1}
    TXKEYED=${TXKEYED:-1}

    log "Node status: RXKEYED='$RXKEYED', TXKEYED='$TXKEYED'"
    return 0
}

# --- WAIT FOR IDLE ---
# Waits up to IDLE_WAIT_TIMEOUT seconds for the repeater to go idle.
# If it does not go idle in time, the callback is called anyway (forced).
# Usage: wait_for_idle <description> <callback_function>
wait_for_idle() {
    local description="$1"
    local callback="$2"
    local start_wait
    start_wait=$(date +%s)

    log "Waiting for repeater to be idle before: $description"

    while :; do
        if get_keyed_status; then
            if [[ "$RXKEYED" == "0" && "$TXKEYED" == "0" ]]; then
                log "Repeater is idle. Proceeding with: $description"
                $callback
                return 0
            else
                log "Repeater is busy. Rechecking in 20 seconds..."
            fi
        else
            log "Could not parse node status. Retrying in 20 seconds..."
        fi

        if (( $(date +%s) - start_wait >= IDLE_WAIT_TIMEOUT )); then
            log "Timeout waiting for idle before $description. Forcing continuation."
            $callback
            return 0
        fi

        sleep 20
    done
}

# ============================================================
# STEP 1: Optional early announcement (uncomment to enable)
# ============================================================
# do_early_announce() {
#     play "$EARLY_ANNOUNCE"
#     sleep "$EARLY_TIME"
# }
# wait_for_idle "early announcement" do_early_announce

# ============================================================
# STEP 2: Wait for idle, play connect announcement, then connect
# ============================================================
do_connect() {
    # Uncomment the two lines below to play a connection announcement before linking.
    # The CONNECT_ANNOUNCE_TIME delay ensures the announcement finishes before connecting,
    # so it does not go out over the linked node.
    # play "$CONNECT_ANNOUNCE"
    # sleep "$CONNECT_ANNOUNCE_TIME"

    log "Connecting to node $TARGET..."
    if ! run_asterisk_cmd "rpt fun $NODE *3$TARGET"; then
        log "ERROR: Connect command failed. Check rpt.conf iLink entries and permissions."
        exit 1
    fi
    log "Connect command sent to node $TARGET."
}

preflight_check
wait_for_idle "connection" do_connect

log "Connected. Waiting $NET_SETTLE_TIME seconds before starting idle monitoring..."
sleep "$NET_SETTLE_TIME"

# ============================================================
# STEP 3: Monitor for idle time and disconnect when net ends
# ============================================================
log "Starting idle monitoring (idle limit: $IDLE_LIMIT seconds, poll interval: $IDLE_POLL_INTERVAL seconds)..."

LAST_ACTIVITY=$(date +%s)

while :; do
    if get_keyed_status; then
        CURRENT_TIME=$(date +%s)

        if [[ "$RXKEYED" == "1" || "$TXKEYED" == "1" ]]; then
            LAST_ACTIVITY=$CURRENT_TIME
            log "Activity detected. Idle timer reset."
        else
            IDLE_TIME=$(( CURRENT_TIME - LAST_ACTIVITY ))
            log "Node idle for $IDLE_TIME seconds (limit: $IDLE_LIMIT)."

            if (( IDLE_TIME >= IDLE_LIMIT )); then
                log "Idle limit reached. Disconnecting from node $TARGET..."

                if ! run_asterisk_cmd "rpt fun $NODE *1$TARGET"; then
                    log "WARNING: Disconnect command may have failed. Check node status manually."
                fi

                sleep 5

                # Uncomment to play a disconnection announcement after leaving the net.
                # play "$DISCONNECT_ANNOUNCE"

                log "Disconnected from node $TARGET. Script complete."
                exit 0
            fi
        fi
    else
        log "Could not retrieve node status. Will retry next poll."
    fi

    sleep "$IDLE_POLL_INTERVAL"
done
