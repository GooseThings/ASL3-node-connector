#!/bin/bash

#############################################
# ASL3 Node Connector - Setup & Permission Checker
# By Goose - N8GMZ - 2025
# https://github.com/GooseThings/ASL3-node-connector/
#
# Run this script to configure ASL3-node-connector.sh
# and verify that your system permissions are correct.
#
# Usage:
#   sudo bash aslnc-setup.sh
#############################################

SCRIPT_TARGET="/usr/local/bin/ASL3-node-connector.sh"
CONF_FILE="/etc/asl3-node-connector.conf"
AUDIO_DIR="/var/lib/asterisk/sounds/custom"
LOGFILE="/var/log/ASL3-node-connector.log"
ASTERISK_BIN="/usr/sbin/asterisk"
CRON_USER="root"

# Terminal formatting
BOLD="\e[1m"
DIM="\e[2m"
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
CYAN="\e[36m"
RESET="\e[0m"

# -----------------------------------------------
# Helpers
# -----------------------------------------------

header() {
    clear
    echo -e "${BOLD}${CYAN}"
    echo "=============================================="
    echo "  ASL3 Node Connector -- Setup & Checker"
    echo "  N8GMZ / GooseThings"
    echo "=============================================="
    echo -e "${RESET}"
}

pause() {
    echo ""
    read -rp "Press ENTER to continue..."
}

confirm() {
    local prompt="${1:-Are you sure?} [y/N] "
    local answer
    read -rp "$prompt" answer
    [[ "${answer,,}" == "y" ]]
}

pass() { echo -e "  ${GREEN}[PASS]${RESET}  $*"; }
fail() { echo -e "  ${RED}[FAIL]${RESET}  $*"; }
warn() { echo -e "  ${YELLOW}[WARN]${RESET}  $*"; }
info() { echo -e "  ${CYAN}[INFO]${RESET}  $*"; }

# -----------------------------------------------
# Permission Checker
# -----------------------------------------------

check_permissions() {
    header
    echo -e "${BOLD}Permission & Environment Check${RESET}"
    echo ""

    local issues=0

    # 1. Running as root or with sudo
    if [[ $EUID -eq 0 ]]; then
        pass "Running as root."
    else
        warn "Not running as root. Some checks may not be accurate. Consider using 'sudo'."
        issues=$((issues + 1))
    fi

    echo ""
    echo -e "${DIM}--- Asterisk ---${RESET}"

    # 2. Asterisk binary exists and is executable
    if [[ -x "$ASTERISK_BIN" ]]; then
        pass "Asterisk binary found and executable at $ASTERISK_BIN"
    else
        fail "Asterisk binary not found or not executable at $ASTERISK_BIN"
        info "Install AllStarLink 3: https://allstarlink.github.io"
        issues=$((issues + 1))
    fi

    # 3. Asterisk service is running
    if systemctl is-active --quiet asterisk 2>/dev/null; then
        pass "Asterisk service is currently running."
    else
        fail "Asterisk service does not appear to be running."
        info "Try: sudo systemctl start asterisk"
        issues=$((issues + 1))
    fi

    # 4. Asterisk user exists
    if id asterisk &>/dev/null; then
        pass "User 'asterisk' exists on this system."
    else
        fail "User 'asterisk' does not exist. ASL3 may not be installed correctly."
        issues=$((issues + 1))
    fi

    echo ""
    echo -e "${DIM}--- Main Script ---${RESET}"

    # 5. Script exists at target location
    if [[ -f "$SCRIPT_TARGET" ]]; then
        pass "Script found at $SCRIPT_TARGET"
    else
        warn "Script not found at $SCRIPT_TARGET"
        info "Copy ASL3-node-connector.sh to $SCRIPT_TARGET, or run the install option from the main menu."
        issues=$((issues + 1))
    fi

    # 6. Script is executable
    if [[ -f "$SCRIPT_TARGET" ]]; then
        if [[ -x "$SCRIPT_TARGET" ]]; then
            pass "Script is executable."
        else
            fail "Script is NOT executable."
            info "Fix with: sudo chmod +x $SCRIPT_TARGET"
            issues=$((issues + 1))
        fi

        # 7. Script permissions (should be 755 or similar)
        local script_perms
        script_perms=$(stat -c "%a" "$SCRIPT_TARGET" 2>/dev/null)
        if [[ "$script_perms" == "755" || "$script_perms" == "750" || "$script_perms" == "700" ]]; then
            pass "Script permissions are $script_perms (OK)."
        else
            warn "Script permissions are $script_perms. Recommended: 755."
            info "Fix with: sudo chmod 755 $SCRIPT_TARGET"
        fi

        # 8. Script owner
        local script_owner
        script_owner=$(stat -c "%U:%G" "$SCRIPT_TARGET" 2>/dev/null)
        if [[ "$script_owner" == "root:root" ]]; then
            pass "Script is owned by root:root."
        else
            warn "Script is owned by $script_owner (expected root:root)."
            info "Fix with: sudo chown root:root $SCRIPT_TARGET"
        fi
    fi

    echo ""
    echo -e "${DIM}--- Audio Files ---${RESET}"

    # 9. Audio directory exists
    if [[ -d "$AUDIO_DIR" ]]; then
        pass "Audio directory exists at $AUDIO_DIR"
    else
        warn "Audio directory not found at $AUDIO_DIR"
        info "Create it with: sudo mkdir -p $AUDIO_DIR"
        info "Then set ownership: sudo chown -R asterisk:asterisk $AUDIO_DIR"
        issues=$((issues + 1))
    fi

    # 10. Audio directory ownership
    if [[ -d "$AUDIO_DIR" ]]; then
        local audio_owner
        audio_owner=$(stat -c "%U:%G" "$AUDIO_DIR" 2>/dev/null)
        if [[ "$audio_owner" == "asterisk:asterisk" ]]; then
            pass "Audio directory is owned by asterisk:asterisk."
        else
            fail "Audio directory is owned by $audio_owner (expected asterisk:asterisk)."
            info "Fix with: sudo chown -R asterisk:asterisk $AUDIO_DIR"
            issues=$((issues + 1))
        fi

        # 11. Audio file permissions (check .wav and .ulaw files)
        local bad_perms=0
        while IFS= read -r -d '' f; do
            local perms
            perms=$(stat -c "%a" "$f" 2>/dev/null)
            if [[ "$perms" != "644" ]]; then
                bad_perms=$((bad_perms + 1))
            fi
        done < <(find "$AUDIO_DIR" \( -name "*.wav" -o -name "*.ulaw" \) -print0 2>/dev/null)

        if [[ $bad_perms -eq 0 ]]; then
            pass "All audio files have correct permissions (644)."
        else
            fail "$bad_perms audio file(s) do not have 644 permissions."
            info "Fix with: sudo find $AUDIO_DIR -type f -exec chmod 644 {} +"
            issues=$((issues + 1))
        fi
    fi

    echo ""
    echo -e "${DIM}--- Configuration ---${RESET}"

    # Config file exists with NODE/TARGET set
    if [[ -f "$CONF_FILE" ]]; then
        local conf_node conf_target
        conf_node=$(grep -E "^NODE=" "$CONF_FILE" 2>/dev/null | tail -1 | cut -d= -f2 | tr -d ' "')
        conf_target=$(grep -E "^TARGET=" "$CONF_FILE" 2>/dev/null | tail -1 | cut -d= -f2 | tr -d ' "')
        if [[ "$conf_node" =~ ^[0-9]+$ && "$conf_target" =~ ^[0-9]+$ ]]; then
            pass "Config file $CONF_FILE sets NODE=$conf_node TARGET=$conf_target."
        else
            fail "Config file $CONF_FILE exists but NODE/TARGET are not set correctly."
            info "Run the Configure option from the main menu."
            issues=$((issues + 1))
        fi
    else
        fail "Config file $CONF_FILE not found — the script will refuse to run."
        info "Run the Configure option from the main menu to create it."
        issues=$((issues + 1))
    fi

    echo ""
    echo -e "${DIM}--- Log File ---${RESET}"

    # 12. Log directory is writable
    local log_dir
    log_dir=$(dirname "$LOGFILE")
    if [[ -w "$log_dir" ]]; then
        pass "Log directory $log_dir is writable."
    else
        fail "Log directory $log_dir is not writable."
        info "Fix with: sudo chmod 755 $log_dir"
        issues=$((issues + 1))
    fi

    # 13. Log file writable (if it exists)
    if [[ -f "$LOGFILE" ]]; then
        if [[ -w "$LOGFILE" ]]; then
            pass "Log file $LOGFILE is writable."
        else
            fail "Log file $LOGFILE exists but is not writable."
            info "Fix with: sudo chmod 644 $LOGFILE"
            issues=$((issues + 1))
        fi
    else
        info "Log file $LOGFILE does not exist yet. It will be created on first run."
    fi

    echo ""
    echo -e "${DIM}--- rpt.conf Link Commands ---${RESET}"

    # 14. Check if iLink commands 811/813 are uncommented in rpt.conf
    local rpt_conf="/etc/asterisk/rpt.conf"
    if [[ -f "$rpt_conf" ]]; then
        # Check for the iLink section and whether 811/813 are active (not commented out)
        local link_811 link_813 ilink_811 ilink_813
        link_811=$(grep -E "^\s*11\s*=" "$rpt_conf" 2>/dev/null | head -1)
        link_813=$(grep -E "^\s*13\s*=" "$rpt_conf" 2>/dev/null | head -1)
        ilink_811=$(grep -E "^\s*811\s*=" "$rpt_conf" 2>/dev/null | head -1)
        ilink_813=$(grep -E "^\s*813\s*=" "$rpt_conf" 2>/dev/null | head -1)

        if [[ -n "$link_811" ]]; then
            pass "rpt.conf link command 11 appears active."
        else
            warn "rpt.conf link command 11 may be commented out."
            info "Use 'sudo asl-menu' -> Expert Configuration -> rpt.conf to uncomment it."
        fi

        if [[ -n "$link_813" ]]; then
            pass "rpt.conf link command 13 appears active."
        else
            warn "rpt.conf link command 13 may be commented out."
        fi

        if [[ -n "$ilink_811" ]]; then
            pass "rpt.conf iLink command 811 appears active."
        else
            warn "rpt.conf iLink command 811 may be commented out."
            info "Use 'sudo asl-menu' -> Expert Configuration -> rpt.conf to uncomment it."
        fi

        if [[ -n "$ilink_813" ]]; then
            pass "rpt.conf iLink command 813 appears active."
        else
            warn "rpt.conf iLink command 813 may be commented out."
        fi
    else
        warn "Could not find rpt.conf at $rpt_conf. Skipping rpt.conf checks."
    fi

    echo ""
    echo -e "${DIM}--- Cron ---${RESET}"

    # 15. Check if a crontab entry exists for the script
    if crontab -l -u "$CRON_USER" 2>/dev/null | grep -q "$SCRIPT_TARGET"; then
        pass "A crontab entry for $SCRIPT_TARGET was found."
    else
        info "No crontab entry found for $SCRIPT_TARGET. You will need to add one to schedule the script."
    fi

    echo ""
    echo "----------------------------------------------"
    if [[ $issues -eq 0 ]]; then
        echo -e "${GREEN}${BOLD}All checks passed. Your system looks ready.${RESET}"
    else
        echo -e "${YELLOW}${BOLD}$issues issue(s) found. Review the items marked [FAIL] or [WARN] above.${RESET}"
    fi
    echo "----------------------------------------------"

    pause
}

# -----------------------------------------------
# Fix Permissions (auto-apply common fixes)
# -----------------------------------------------

fix_permissions() {
    header
    echo -e "${BOLD}Auto-Fix Permissions${RESET}"
    echo ""
    echo "This will apply the following fixes:"
    echo "  - chmod +x and chmod 755 on $SCRIPT_TARGET"
    echo "  - chown root:root on $SCRIPT_TARGET"
    echo "  - chown -R asterisk:asterisk on $AUDIO_DIR"
    echo "  - chmod -R 644 on audio files in $AUDIO_DIR"
    echo ""

    if ! confirm "Apply these fixes now?"; then
        echo "Cancelled."
        pause
        return
    fi

    if [[ -f "$SCRIPT_TARGET" ]]; then
        chmod +x "$SCRIPT_TARGET"
        chmod 755 "$SCRIPT_TARGET"
        chown root:root "$SCRIPT_TARGET"
        echo -e "  ${GREEN}Fixed permissions on $SCRIPT_TARGET${RESET}"
    else
        echo -e "  ${YELLOW}Script not found at $SCRIPT_TARGET -- skipping.${RESET}"
    fi

    if [[ -d "$AUDIO_DIR" ]]; then
        chown -R asterisk:asterisk "$AUDIO_DIR"
        find "$AUDIO_DIR" \( -name "*.wav" -o -name "*.ulaw" \) -exec chmod 644 {} \;
        echo -e "  ${GREEN}Fixed ownership and permissions on $AUDIO_DIR${RESET}"
    else
        echo -e "  ${YELLOW}Audio directory not found at $AUDIO_DIR -- skipping.${RESET}"
    fi

    echo ""
    echo "Done. Run the permission checker to verify."
    pause
}

# -----------------------------------------------
# Configure (writes /etc/asl3-node-connector.conf)
#
# Settings live in a conf file the main script sources at startup, NOT in
# the script itself — so reinstalling/upgrading the script never wipes the
# user's configuration (the old sed-edit-the-script approach did).
# -----------------------------------------------

# conf_get <VAR> — current effective value: conf file wins, else script default.
conf_get() {
    local name="$1" val=""
    if [[ -f "$CONF_FILE" ]]; then
        val=$(grep -E "^${name}=" "$CONF_FILE" 2>/dev/null | tail -1 \
              | cut -d= -f2- | sed 's/[[:space:]]*#.*$//' | tr -d '"' | xargs)
    fi
    if [[ -z "$val" && -f "$SCRIPT_TARGET" ]]; then
        val=$(grep -E "^${name}=" "$SCRIPT_TARGET" 2>/dev/null | head -1 \
              | cut -d= -f2- | sed 's/[[:space:]]*#.*$//' | tr -d '"' | xargs)
    fi
    echo "$val"
}

# ask <prompt> <current> <varname> — prompt with default, store the answer.
ask() {
    local prompt="$1" cur="$2" var="$3" new_val
    read -rp "  ${prompt} [${cur}]: " new_val
    printf -v "$var" '%s' "${new_val:-$cur}"
}

configure_script() {
    header
    echo -e "${BOLD}Configure ASL3 Node Connector${RESET}"
    echo ""
    echo "Settings are stored in $CONF_FILE and survive script upgrades."
    echo "Press ENTER to keep the value shown in brackets."
    echo "For announcements, an empty value (or entering 'none') disables that announcement."
    echo ""

    local c_node c_target c_idle c_settle c_poll c_perm c_audio
    local c_early c_earlytime c_conn c_conntime c_disc c_logfile

    ask "Your node number         " "$(conf_get NODE)"                  c_node
    ask "Target node number       " "$(conf_get TARGET)"                c_target
    ask "Idle limit (seconds)     " "$(conf_get IDLE_LIMIT)"            c_idle
    ask "Net settle time (sec)    " "$(conf_get NET_SETTLE_TIME)"       c_settle
    ask "Idle poll interval (s)   " "$(conf_get IDLE_POLL_INTERVAL)"    c_poll
    ask "Permanent link? (true/false)" "$(conf_get PERMANENT_LINK)"     c_perm
    ask "Audio path               " "$(conf_get AUDIO_PATH)"            c_audio
    ask "Early announcement       " "$(conf_get EARLY_ANNOUNCE)"        c_early
    ask "Early lead time (sec)    " "$(conf_get EARLY_TIME)"            c_earlytime
    ask "Connect announcement     " "$(conf_get CONNECT_ANNOUNCE)"      c_conn
    ask "Connect announce dwell(s)" "$(conf_get CONNECT_ANNOUNCE_TIME)" c_conntime
    ask "Disconnect announcement  " "$(conf_get DISCONNECT_ANNOUNCE)"   c_disc
    ask "Log file path            " "$(conf_get LOGFILE)"               c_logfile

    # 'none' is an explicit way to clear an announcement (plain ENTER keeps it)
    [[ "${c_early,,}" == "none" ]] && c_early=""
    [[ "${c_conn,,}"  == "none" ]] && c_conn=""
    [[ "${c_disc,,}"  == "none" ]] && c_disc=""

    if [[ ! "$c_node" =~ ^[0-9]+$ || ! "$c_target" =~ ^[0-9]+$ ]]; then
        echo ""
        echo -e "${RED}NODE and TARGET must both be set to node numbers. Nothing saved.${RESET}"
        pause
        return
    fi

    cat > "$CONF_FILE" <<EOF
# ASL3 Node Connector configuration
# Written by aslnc-setup.sh on $(date '+%Y-%m-%d %H:%M:%S')
# Sourced by ASL3-node-connector.sh; anything not set here uses the
# script's built-in default.
NODE=$c_node
TARGET=$c_target
IDLE_LIMIT=$c_idle
NET_SETTLE_TIME=$c_settle
IDLE_POLL_INTERVAL=$c_poll
PERMANENT_LINK=$c_perm
AUDIO_PATH="$c_audio"
EARLY_ANNOUNCE="$c_early"
EARLY_TIME=$c_earlytime
CONNECT_ANNOUNCE="$c_conn"
CONNECT_ANNOUNCE_TIME=$c_conntime
DISCONNECT_ANNOUNCE="$c_disc"
LOGFILE="$c_logfile"
EOF
    chmod 644 "$CONF_FILE"

    echo ""
    echo -e "${GREEN}Configuration saved to $CONF_FILE${RESET}"
    pause
}

# -----------------------------------------------
# Install: copy script and set up file structure
# -----------------------------------------------

install_script() {
    header
    echo -e "${BOLD}Install ASL3-node-connector.sh${RESET}"
    echo ""

    # Find the script next to this setup file, or in the current directory
    local source_script
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    if [[ -f "$script_dir/ASL3-node-connector.sh" ]]; then
        source_script="$script_dir/ASL3-node-connector.sh"
    elif [[ -f "./ASL3-node-connector.sh" ]]; then
        source_script="./ASL3-node-connector.sh"
    else
        echo -e "${RED}Cannot find ASL3-node-connector.sh.${RESET}"
        echo "Make sure ASL3-node-connector.sh is in the same directory as this setup script."
        pause
        return
    fi

    echo "Source: $source_script"
    echo "Destination: $SCRIPT_TARGET"
    echo ""

    if [[ -f "$SCRIPT_TARGET" ]]; then
        warn "Script already exists at $SCRIPT_TARGET."
        if ! confirm "Overwrite it?"; then
            echo "Install cancelled."
            pause
            return
        fi
    fi

    cp "$source_script" "$SCRIPT_TARGET"
    chmod +x "$SCRIPT_TARGET"
    chmod 755 "$SCRIPT_TARGET"
    chown root:root "$SCRIPT_TARGET"

    echo -e "${GREEN}Script installed to $SCRIPT_TARGET${RESET}"

    # Create audio directory if it does not exist
    if [[ ! -d "$AUDIO_DIR" ]]; then
        if confirm "Create audio directory at $AUDIO_DIR?"; then
            mkdir -p "$AUDIO_DIR"
            chown -R asterisk:asterisk "$AUDIO_DIR"
            echo -e "${GREEN}Created $AUDIO_DIR${RESET}"
        fi
    fi

    # Offer to install the bundled generic announcements
    if [[ -d "$script_dir/audio" && -d "$AUDIO_DIR" ]]; then
        if confirm "Install the bundled generic announcement WAVs to $AUDIO_DIR?"; then
            cp "$script_dir/audio/"*.wav "$AUDIO_DIR/"
            chown asterisk:asterisk "$AUDIO_DIR"/*.wav
            chmod 644 "$AUDIO_DIR"/*.wav
            echo -e "${GREEN}Installed bundled announcements (use them by name, e.g. 'link-generic-announcement').${RESET}"
        fi
    fi

    # Create log file stub
    if [[ ! -f "$LOGFILE" ]]; then
        touch "$LOGFILE"
        chmod 644 "$LOGFILE"
        echo -e "${GREEN}Created log file at $LOGFILE${RESET}"
    fi

    echo ""
    if [[ -f "$CONF_FILE" ]]; then
        echo "Installation complete. Existing configuration at $CONF_FILE was kept."
    else
        echo "Installation complete. Use the Configure option to set your node numbers."
        echo "(The script will not run until $CONF_FILE exists with NODE and TARGET set.)"
    fi
    pause
}

# -----------------------------------------------
# Crontab Management
# -----------------------------------------------

manage_crontab() {
    header
    echo -e "${BOLD}Crontab Management${RESET}"
    echo ""
    echo "Scheduled crontab entries for $SCRIPT_TARGET:"
    echo ""

    local existing
    existing=$(crontab -l -u "$CRON_USER" 2>/dev/null | grep "$SCRIPT_TARGET" || true)

    if [[ -z "$existing" ]]; then
        echo "  (none found)"
    else
        echo "$existing" | while IFS= read -r line; do
            echo "  $line"
        done
    fi

    echo ""
    echo "Options:"
    echo "  1) Add a new scheduled run"
    echo "  2) Remove all entries for this script"
    echo "  3) Open crontab in editor (manual)"
    echo "  4) Back"
    echo ""
    read -rp "Selection: " choice

    case "$choice" in
        1)
            echo ""
            echo "Enter the cron schedule for when to run the script."
            echo "Format: minute hour day month weekday"
            echo "  Weekdays: 0=Sunday, 1=Monday, ..., 3=Wednesday, ..., 6=Saturday"
            echo ""
            echo "Example for every Wednesday at 7:48 PM: 48 19 * * 3"
            echo ""
            read -rp "Schedule: " sched
            if [[ -z "$sched" ]]; then
                echo "No schedule entered. Cancelled."
            else
                (crontab -l -u "$CRON_USER" 2>/dev/null; echo "$sched $SCRIPT_TARGET") | crontab -u "$CRON_USER" -
                echo -e "${GREEN}Crontab entry added: $sched $SCRIPT_TARGET${RESET}"
            fi
            ;;
        2)
            if confirm "Remove all crontab entries for $SCRIPT_TARGET?"; then
                crontab -l -u "$CRON_USER" 2>/dev/null \
                    | grep -v "$SCRIPT_TARGET" \
                    | crontab -u "$CRON_USER" -
                echo -e "${GREEN}Entries removed.${RESET}"
            fi
            ;;
        3)
            crontab -e -u "$CRON_USER"
            ;;
        4)
            return
            ;;
        *)
            echo "Invalid selection."
            ;;
    esac

    pause
}

# -----------------------------------------------
# View Log
# -----------------------------------------------

view_log() {
    header
    echo -e "${BOLD}Log Viewer: $LOGFILE${RESET}"
    echo ""

    if [[ ! -f "$LOGFILE" ]]; then
        echo "Log file does not exist yet. It will be created on first run."
        pause
        return
    fi

    local line_count
    line_count=$(wc -l < "$LOGFILE")
    echo "Total log entries: $line_count"
    echo ""
    echo "Options:"
    echo "  1) View last 50 lines"
    echo "  2) View entire log"
    echo "  3) Clear log"
    echo "  4) Back"
    echo ""
    read -rp "Selection: " choice

    case "$choice" in
        1) tail -n 50 "$LOGFILE" | less ;;
        2) less "$LOGFILE" ;;
        3)
            if confirm "Clear the log file?"; then
                : > "$LOGFILE"
                echo "Log cleared."
            fi
            ;;
        4) return ;;
        *) echo "Invalid selection." ;;
    esac

    pause
}

# -----------------------------------------------
# Dry Run
# -----------------------------------------------

run_dry_run() {
    header
    echo -e "${BOLD}Dry Run${RESET}"
    echo ""
    echo "This will run the script in dry-run mode."
    echo "No Asterisk commands will be executed, but all logic will run."
    echo "Output will also be logged to $LOGFILE"
    echo ""

    if [[ ! -f "$SCRIPT_TARGET" ]]; then
        echo -e "${RED}Script not found at $SCRIPT_TARGET. Please install first.${RESET}"
        pause
        return
    fi

    if ! confirm "Start dry run now?"; then
        return
    fi

    bash "$SCRIPT_TARGET" --dry-run
    pause
}

# -----------------------------------------------
# Main Menu
# -----------------------------------------------

main_menu() {
    while :; do
        header
        echo "  1)  Install script to $SCRIPT_TARGET"
        echo "  2)  Configure script settings (node numbers, timers, paths)"
        echo "  3)  Run permission & environment check"
        echo "  4)  Auto-fix common permission issues"
        echo "  5)  Manage crontab schedule"
        echo "  6)  View log"
        echo "  7)  Run dry run (test mode)"
        echo "  8)  Exit"
        echo ""
        read -rp "Selection: " choice

        case "$choice" in
            1) install_script ;;
            2) configure_script ;;
            3) check_permissions ;;
            4) fix_permissions ;;
            5) manage_crontab ;;
            6) view_log ;;
            7) run_dry_run ;;
            8) echo "Exiting."; exit 0 ;;
            *) echo "Invalid selection."; sleep 1 ;;
        esac
    done
}

# -----------------------------------------------
# Entry point
# -----------------------------------------------

if [[ $EUID -ne 0 ]]; then
    echo -e "${YELLOW}Warning: This script should be run as root (or with sudo) for full functionality.${RESET}"
    echo ""
    if ! confirm "Continue anyway?"; then
        exit 1
    fi
fi

main_menu
