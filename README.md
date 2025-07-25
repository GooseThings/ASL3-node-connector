 # ASL-node-connector
 This assumes you have a working instance of AllStarLink 3 running already.
 ## Setup
 * Download ```ASL-node-connector.sh``` to ```/usr/local/bin```
 * Download audio files to: ```/var/lib/asterisk/sounds/custom``` (optional)
 * Setup the shell script by editing the .sh file: ```sudo nano /usr/local/sbin/ASL3-node-connector.sh```
 * Run automatically at certain times via crontab. The 10 minute warning/connect/disconnect announcements are all baked in to the shell script.
   * Example of crontab command to run at 7:48PM on Wednesdays: ```48 19 * * 3 /usr/local/bin/WMEC-autoconnect-disconnect.sh >> /var/log/wmec-cron.log 2>&1```
 * Don't forget to give the shell script permission to execute:
   * ```chmod +x /usr/local/bin/ASL3-node-connector.sh```
   * ```chmod 755 /usr/local/bin/ASL3-nodeconnector.sh```
 * Then give Asterisk ownership of the sound files ```chown -R asterisk:asterisk /var/lib/asterisk/sounds/custom/```
 * And read permissions ```chmod -R 644 /var/lib/asterisk/sounds/custom/```
 ## Dry Run
 You can test that everything is working by running ```ASL3-node-connector.sh --dry-run``` then checking the log after in ```/var/log/ASL3-node-connector.log```
