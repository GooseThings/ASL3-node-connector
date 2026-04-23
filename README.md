# ASL3 Node Connector (ASLNC)

ASL3 Node Connector is a shell script that automatically connects your AllStarLink 3 node to another node at a scheduled time, monitors the linked node for activity, and disconnects when the net has been idle for a configurable period.

It is designed to run unattended from cron, so your node connects at net time and disconnects itself when the net ends with no manual intervention required.

---

## How it works

1. The script waits for your repeater to be idle, then sends the connect command to ASL.
2. After connecting, it pauses for a configurable settle time to let the net get started.
3. It then polls the node at regular intervals, tracking how long the node has been idle.
4. When the idle time exceeds the configured limit, it sends the disconnect command and exits.

Optional audio announcements can be played before connecting and after disconnecting. These are disabled by default and can be enabled by editing the script.

---

## Requirements

- AllStarLink 3 running and configured on your system
- Asterisk (installed as part of ASL3)
- bash
- A working node number registered with AllStarLink
- The iLink commands in `rpt.conf` must be uncommented (see below)

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
- Install the script to `/usr/local/bin`
- Set your node numbers, timers, and paths
- Check that all permissions and system requirements are correct
- Automatically fix common permission problems
- Add or remove crontab schedule entries
- View the log file
- Run a dry run to test the script without sending any commands

### Step 3: Install manually (alternative to the setup script)

If you prefer to install manually:

```bash
sudo cp ASL3-node-connector.sh /usr/local/bin/ASL3-node-connector.sh
sudo chmod 755 /usr/local/bin/ASL3-node-connector.sh
sudo chown root:root /usr/local/bin/ASL3-node-connector.sh
```

---

## Configuration

Open the script in a text editor:

```bash
sudo nano /usr/local/bin/ASL3-node-connector.sh
```

Edit the settings section near the top of the file:

| Setting | Description |
|---|---|
| `NODE` | Your local ASL3 node number |
| `TARGET` | The node number you want to connect to |
| `IDLE_LIMIT` | Seconds of inactivity before auto-disconnect (default: 180) |
| `AUDIO_PATH` | Directory where your WAV announcement files are stored |
| `EARLY_ANNOUNCE` | Filename of the early warning announcement (without extension) |
| `EARLY_TIME` | Seconds before connecting to play the early announcement |
| `CONNECT_ANNOUNCE` | Filename of the connection announcement (without extension) |
| `CONNECT_ANNOUNCE_TIME` | How long to wait after playing the connect announcement before linking. This must be at least as long as the announcement, or the announcement will play over the linked node. |
| `DISCONNECT_ANNOUNCE` | Filename of the disconnection announcement (without extension) |
| `LOGFILE` | Full path to the log file |
| `NET_SETTLE_TIME` | Seconds to wait after connecting before starting idle monitoring (default: 300) |
| `IDLE_POLL_INTERVAL` | How often to check for idle status in seconds (default: 30) |

If you do not want audio announcements, leave the filename variables set to empty strings (`""`). If you want the early announcement or connect/disconnect announcements enabled, uncomment the relevant lines in the script as directed by the inline comments.

---

## Configuring rpt.conf

The script uses Asterisk's `rpt fun` commands to connect and disconnect nodes. These commands require specific entries in `rpt.conf` to be uncommented. By default they are commented out in a fresh ASL3 installation.

To uncomment them:

```bash
sudo asl-menu
```

Navigate to: Expert Configuration > rpt.conf

Find the "Link commands" section and uncomment lines 11 and 13.
Find the "iLink commands" section and uncomment lines 811 and 813.

The recommended setup is to use 813 to make a permanent connection and 811 to disconnect a permanent connection. This is more reliable than the `*3` / `*1` commands if a connection drops during the net.

If you prefer to use `*3` and `*1` instead, you can change the connect and disconnect commands in the script accordingly. The relevant lines are documented in the script with inline comments.

After editing rpt.conf, reload Asterisk:

```bash
sudo systemctl reload asterisk
```

---

## Audio Announcements

Audio files must meet the following requirements for Asterisk to play them:

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
sudo chmod -R 644 /var/lib/asterisk/sounds/custom
```

Then enable the announcement lines in the script by removing the comment characters from the relevant `play` and `sleep` lines.

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

The cron time should be set to when you want the script to start watching for the node to be idle before connecting, not the exact time you want it to connect. If the net starts at 8:00 PM and you want a 10-minute early warning, schedule the script to start at approximately 7:48 PM.

---

## Permission Checker

If the script fails silently or the link commands do not execute, it is often a permissions problem. The setup script includes a built-in permission checker that tests all required conditions:

```bash
sudo bash aslnc-setup.sh
```

Select option 3 from the menu to run the checker. It will report on:

- Whether Asterisk is installed and running
- Whether the script is executable with correct ownership
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

For faster testing, temporarily reduce `IDLE_LIMIT`, `NET_SETTLE_TIME`, and `EARLY_TIME` to small values (such as 10-30 seconds) before running a dry run. Restore them to production values when done.

---

## Log File

The script logs all actions with timestamps to the file specified by `LOGFILE` (default: `/var/log/ASL3-node-connector.log`).

To follow the log in real time while the script is running:

```bash
tail -f /var/log/ASL3-node-connector.log
```

---

## Troubleshooting

**The script runs but the node does not connect.**
Check that the iLink commands 811 and 813 are uncommented in rpt.conf and that Asterisk was reloaded afterward. Run the permission checker to verify the script has execute permissions. Check the log file for error messages from the Asterisk command.

**Audio announcements do not play.**
Confirm the audio files exist at the path configured in `AUDIO_PATH`, that they are in mono 8000 Hz WAV or ulaw format, and that Asterisk owns them (`chown -R asterisk:asterisk`). Check that the `play` lines in the script are uncommented.

**The script exits immediately.**
Check the log file. A pre-flight check failure will cause an immediate exit with an error message explaining what is wrong. Common causes are a missing Asterisk binary or a log directory that is not writable.

**The cron job does not appear to run.**
Make sure the crontab was added to root's crontab (`sudo crontab -e`), not the current user's crontab. Also confirm the script path in the crontab entry matches the installed location exactly.

**Permission denied when executing link commands.**
Run `sudo bash aslnc-setup.sh` and select the permission checker (option 3) and the auto-fix option (option 4). If problems persist, review the rpt.conf iLink section manually.

---

## License

MIT License. See LICENSE file for details.
