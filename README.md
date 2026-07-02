# ASL3 Node Connector (ASLNC)

ASL3 Node Connector is a shell script that automatically connects your AllStarLink 3 node to another node at a scheduled time, monitors the linked node for activity, and disconnects when the net has been idle for a configurable period.

It is designed to run unattended from cron, so your node connects at net time and disconnects itself when the net ends with no manual intervention required.

---

## How it works

1. The script waits for your repeater to be idle, then sends the connect command to ASL.
2. **It verifies the link actually came up** (`rpt lstats`) and retries if it didn't — the Asterisk CLI reports success even when the command silently did nothing, which is the most common install problem.
3. After connecting, it pauses for a configurable settle time to let the net get started.
4. It then polls the node at regular intervals, tracking how long the node has been idle.
5. When the idle time exceeds the configured limit, it sends the disconnect command (verified the same way) and exits.

Optional audio announcements can be played before connecting and after disconnecting. They are played with `rpt localplay`, so they are heard only on your local node — never transmitted over the link.

Only one instance can run per node at a time: if a previous run is still going (for example a net that ran long), an overlapping cron start logs a message and exits instead of fighting over the link.

---

## Requirements

- AllStarLink 3 running and configured on your system
- Asterisk (installed as part of ASL3)
- bash
- A working node number registered with AllStarLink
- The link commands in `rpt.conf` must be uncommented (see below)

---

## Installation

### Step 1: Clone the repository

```bash
sudo git clone https://github.com/GooseThings/ASL3-node-connector.git /usr/local/src/ASL3-node-connector
cd /usr/local/src/ASL3-node-connector
```

### Step 2: Run the setup script (recommended)

The included setup script provides a text-based menu for installing, configuring, and checking permissions. Run it as root:

```bash
sudo bash aslnc-setup.sh
```

From the menu you can:
- Install the script to `/usr/local/bin` (and optionally the bundled generic announcement audio)
- Set your node numbers, timers, paths, and announcements
- Check that all permissions and system requirements are correct
- Automatically fix common permission problems
- Add or remove crontab schedule entries
- View the log file
- Run a dry run to test the script without sending any commands

### Step 3: Install manually (alternative to the setup script)

```bash
sudo cp ASL3-node-connector.sh /usr/local/bin/ASL3-node-connector.sh
sudo chmod 755 /usr/local/bin/ASL3-node-connector.sh
sudo chown root:root /usr/local/bin/ASL3-node-connector.sh
```

Then create `/etc/asl3-node-connector.conf` by hand (see Configuration below). The script refuses to run until `NODE` and `TARGET` are configured.

---

## Configuration

All settings live in `/etc/asl3-node-connector.conf` — **not** in the script itself — so upgrading the script never wipes your configuration. The easiest way to create or change it is the setup menu (`sudo bash aslnc-setup.sh`, option 2). A minimal config looks like:

```bash
NODE=12345
TARGET=67890
```

Any setting not present in the conf file uses the script's built-in default.

| Setting | Default | Description |
|---|---|---|
| `NODE` | *(required)* | Your local ASL3 node number |
| `TARGET` | *(required)* | The node number you want to connect to |
| `IDLE_LIMIT` | `180` | Seconds of inactivity before auto-disconnect |
| `NET_SETTLE_TIME` | `300` | Seconds to wait after connecting before idle monitoring starts |
| `IDLE_POLL_INTERVAL` | `30` | How often to check for idle status, in seconds |
| `PERMANENT_LINK` | `false` | `true` uses the permanent-link commands `*813`/`*811`; `false` uses `*3`/`*1` |
| `AUDIO_PATH` | `/var/lib/asterisk/sounds/custom` | Directory where your announcement files are stored |
| `EARLY_ANNOUNCE` | *(empty = disabled)* | Filename of the early warning announcement (no extension) |
| `EARLY_TIME` | `600` | Seconds between the early announcement and the connect phase |
| `CONNECT_ANNOUNCE` | *(empty = disabled)* | Filename of the connection announcement (no extension) |
| `CONNECT_ANNOUNCE_TIME` | `20` | Dwell after playing the connect announcement, before linking. Must be at least as long as the audio, or it will still be playing when the link comes up and be heard on the far node. |
| `DISCONNECT_ANNOUNCE` | *(empty = disabled)* | Filename of the disconnection announcement (no extension) |
| `LOGFILE` | `/var/log/ASL3-node-connector.log` | Full path to the log file |
| `LOG_MAX_BYTES` | `1048576` | Log rotates to `.old` when it grows past this size |

Announcements are enabled simply by setting their filename — no script editing required. Leave them empty (`""`) to disable.

---

## Configuring rpt.conf

The script uses Asterisk's `rpt fun` commands to connect and disconnect nodes. These commands require specific entries in the `[functions]` section of `rpt.conf` to be uncommented. By default some are commented out in a fresh ASL3 installation.

To uncomment them:

```bash
sudo asl-menu
```

Navigate to: Expert Configuration > rpt.conf

- With the default `PERMANENT_LINK=false`, the script uses `*3` (connect) and `*1` (disconnect) — functions `1` and `3` must be active.
- With `PERMANENT_LINK=true`, the script uses `*813` (permanently connect) and `*811` (disconnect a permanent link) — functions `811` and `813` must be active. A permanent link is more reliable for nets because ASL automatically re-establishes it if the connection drops mid-net.

After editing rpt.conf, reload Asterisk:

```bash
sudo systemctl reload asterisk
```

If the required functions are commented out, the connect command does nothing — Asterisk does not report an error. The script detects this by checking the actual link state afterward, retries three times, and logs a clear error telling you which functions to uncomment.

---

## Audio Announcements

The repository ships three ready-to-use generic announcements in the `audio/` folder (a 10-minute warning, a link announcement, and a disconnect announcement); the setup script offers to install them for you. To use your own audio, files must meet the following requirements for Asterisk to play them:

- Format: WAV or ulaw
- Channels: mono
- Sample rate: 8000 Hz

To convert an MP3 to the correct format using ffmpeg:

```bash
ffmpeg -i input.mp3 -ac 1 -ar 8000 -sample_fmt s16 output.wav
```

If ffmpeg is not installed:

```bash
sudo apt install ffmpeg
```

Place the converted files in the audio directory (default: `/var/lib/asterisk/sounds/custom`).

After placing files, set correct ownership and permissions so Asterisk can read them:

```bash
sudo chown -R asterisk:asterisk /var/lib/asterisk/sounds/custom
sudo find /var/lib/asterisk/sounds/custom -type f -exec chmod 644 {} +
```

(Do not use `chmod -R 644` on the directory itself — that strips the directory's execute bit and makes the files unreachable.)

Then set the announcement names (without extension) in `/etc/asl3-node-connector.conf`.

Announcements are played with `rpt localplay`, so they go out over your local node's transmitter only — they are not sent to the target node or any other connected links.

---

## Scheduling with Cron

The script is intended to be run automatically via cron. To add a crontab entry:

```bash
sudo crontab -e
```

Add a line in the following format:

```
minute hour * * weekday /usr/local/bin/ASL3-node-connector.sh
```

Weekday numbering: 0 = Sunday, 1 = Monday, 2 = Tuesday, 3 = Wednesday, 4 = Thursday, 5 = Friday, 6 = Saturday.

Example to run every Wednesday at 7:48 PM:

```
48 19 * * 3 /usr/local/bin/ASL3-node-connector.sh
```

The cron time should be set to when you want the script to start, not the exact time you want it to connect. If `EARLY_ANNOUNCE` is set, the script plays it once the repeater is idle and then waits `EARLY_TIME` seconds before connecting — so for an 8:00 PM net with a 10-minute warning, schedule the script for about 7:48 PM with `EARLY_TIME=600`.

If a previous run is still going when cron fires again, the new run exits immediately (single-instance lock), so overlapping schedules are safe.

---

## Permission Checker

If the script fails silently or the link commands do not execute, it is often a permissions problem. The setup script includes a built-in permission checker that tests all required conditions:

```bash
sudo bash aslnc-setup.sh
```

Select option 3 from the menu to run the checker. It will report on:

- Whether Asterisk is installed and running
- Whether the script is executable with correct ownership
- Whether the config file exists with NODE and TARGET set
- Whether audio files have correct ownership and permissions
- Whether the log directory is writable
- Whether the required rpt.conf entries appear to be active
- Whether a crontab entry exists

Select option 4 to automatically apply the most common fixes.

---

## Dry Run

To test the script without sending any actual commands to Asterisk:

```bash
/usr/local/bin/ASL3-node-connector.sh --dry-run
```

All logic runs normally and all steps are logged, but no Asterisk commands are executed. Check the log to see what would have happened:

```bash
cat /var/log/ASL3-node-connector.log
```

For faster testing, temporarily reduce `IDLE_LIMIT`, `NET_SETTLE_TIME`, and `EARLY_TIME` to small values (such as 10-30 seconds) in the conf file. Restore them to production values when done.

---

## Log File

The script logs all actions with timestamps to the file specified by `LOGFILE` (default: `/var/log/ASL3-node-connector.log`). When the log exceeds `LOG_MAX_BYTES` (1 MB by default) it is rotated to `<logfile>.old` at the next script start, so it cannot grow unbounded.

To follow the log in real time while the script is running:

```bash
tail -f /var/log/ASL3-node-connector.log
```

---

## Troubleshooting

**The script runs but the node does not connect.**
The log will now tell you directly: if the link never comes up, the script retries three times and logs which rpt.conf `[functions]` entries need to be uncommented (`1`/`3` for normal links, `811`/`813` for permanent links). Reload Asterisk after editing rpt.conf.

**Audio announcements do not play.**
Confirm the audio files exist at the path configured in `AUDIO_PATH`, that they are in mono 8000 Hz WAV or ulaw format, and that Asterisk owns them (`chown -R asterisk:asterisk`). The log records a warning naming the exact missing file when an announcement can't be found.

**The script exits immediately.**
Check the log file (and the console output if run by hand). Pre-flight checks fail fast with a message when `NODE`/`TARGET` are unset or the Asterisk binary is missing. "Another instance is already running" means a previous run is still active — or a stale process is stuck; find it with `pgrep -a -f ASL3-node-connector`.

**The cron job does not appear to run.**
Make sure the crontab was added to root's crontab (`sudo crontab -e`), not the current user's crontab. Also confirm the script path in the crontab entry matches the installed location exactly.

**Permission denied when executing link commands.**
Run `sudo bash aslnc-setup.sh` and select the permission checker (option 3) and the auto-fix option (option 4). If problems persist, review the rpt.conf functions section manually.

---

## Upgrading from older versions

Older versions stored settings directly in the script and enabled announcements by uncommenting lines. When upgrading:

1. Note your current settings from the top of your installed `/usr/local/bin/ASL3-node-connector.sh`.
2. Install the new script (setup menu option 1).
3. Enter those settings in the Configure menu (option 2) — they now live in `/etc/asl3-node-connector.conf` and will survive future upgrades.

Announcements now use `rpt localplay` (local node only) instead of `rpt playback` (all connected links).

---

## License

MIT License. See LICENSE file for details.
