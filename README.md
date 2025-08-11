 # NOTE: ASLNC has a bug
 * 08/07/2025 - The current version is hanging and going into a infinite loop. Working on a fix. Download at your own risk right now.
 # ASL Node Connector (ASLNC)
 This assumes you have a working instance of AllStarLink 3 running already.
 ## Setup
 * Download ```ASL-node-connector.sh``` to ```/usr/local/bin``` or alternatively:
 * ```git clone https://github.com/GooseThings/ASL3-node-connector.git```
 * Download audio files to: ```/var/lib/asterisk/sounds/custom``` (optional)
 * Setup the shell script by editing the .sh file: ```sudo nano /usr/local/sbin/ASL3-node-connector.sh```
 * Run automatically at certain times via crontab. The 10 minute warning/connect/disconnect announcements are all baked in to the shell script.
   * Example of crontab command to run at 7:48PM on Wednesdays: ```48 19 * * 3 /usr/local/bin/WMEC-autoconnect-disconnect.sh >> /var/log/wmec-cron.log 2>&1```
 * Don't forget to give the shell script permission to execute:
   * ```chmod +x /usr/local/bin/ASL3-node-connector.sh```
   * ```chmod 755 /usr/local/bin/ASL3-nodeconnector.sh```
 * Then give Asterisk ownership of the sound files ```chown -R asterisk:asterisk /var/lib/asterisk/sounds/custom/```
 * And read permissions ```chmod -R 644 /var/lib/asterisk/sounds/custom/```
## Edit the rpt.conf file
You will need to uncomments the following lines:
 * In "Link commands" uncomment 11 and 13
 * In "ilink commands" uncomment 811 and 813
 ## Dry Run
 You can test that everything is working by running ```ASL3-node-connector.sh --dry-run``` then checking the log after in ```/var/log/ASL3-node-connector.log```
 
 It's recommended you adjust the times down for dry runs, unless you want it to take 10-12 minutes for it to complete.
