 # ASL Node Connector (ASLNC) 
 This script is meant to connect your ASL3 node to another node for a regularly scheduled net. It will make an announcement that it is connecting prior to linking (default set to 10 minutes), and then another announcement when it is making the connection. It will monitor the node for traffic during the net, and once it senses that the node has gone idle, it will disconnect, then make a disconnection announcement to let everyone know it is no longer connected.
 ## Release Notes
 * 08/10/2025 - Fixed the infinite loop and added error handling to idle monitoring.
 * 08/07/2025 - The current version is hanging and going into a infinite loop. Working on a fix. Download at your own risk right now.

 ## Setup
 This assumes you have a working instance of AllStarLink 3 running already.
 * Download ```ASL-node-connector.sh``` to ```/usr/local/bin``` or alternatively:
 * ```sudo git clone https://github.com/GooseThings/ASL3-node-connector.git```
 * Download audio files to: ```/var/lib/asterisk/sounds/custom``` (optional)
 * Setup the shell script by editing the .sh file: ```sudo nano /usr/local/bin/ASL3-node-connector.sh```
 * Run automatically at certain times via crontab using the command ```crontab -e```
   * Example of crontab command to run at 7:48PM on Wednesdays: ```48 19 * * 3 /usr/local/bin/ASL3-node-connector.sh >> /var/log/ASLNC-cron.log 2>&1```
 * Don't forget to give the shell script permission to execute:
   * ```sudo chmod +x /usr/local/bin/ASL3-node-connector.sh```
   * ```sudo chmod 755 /usr/local/bin/ASL3-nodeconnector.sh```
 * Then give Asterisk ownership of the sound files ```chown -R asterisk:asterisk /var/lib/asterisk/sounds/custom/```
 * And sounds file read permissions ```chmod -R 644 /var/lib/asterisk/sounds/custom/```
 * NOTE: Sound files have to be wav or ulaw, mono, and 6000Hz, for asterisk to play them. Use ffmpeg, or another audio format conversion software, to convert them to the proper format before setting ownership and permissions.
 * If you do not want sound files to play then blank the file names in the settings section to just: ""
## Edit the rpt.conf file
You will need to uncomments the following lines in **rpt.conf** file:
 * Use the command ```sudo asl-menu``` to enter the ASL screen, go to Expert Configuration, select rpt.conf
 * In "Link commands" uncomment 11 and 13
 * In "iLink commands" uncomment 811 and 813
This lets you execute those commands using the script. They are commented out by default.
It is recommended that you use 813 for the connection (permenent) and 811 to disconnect a permenent connection in case the connection drops during the net.
You can use *3 and *1 if you do not want that.
 ## Dry Run
 You can test that everything is working by running ```ASL3-node-connector.sh --dry-run``` then checking the log after in ```/var/log/ASL3-node-connector.log```
 
 It's recommended you adjust the times down for dry runs, unless you want it to take 10-12 minutes for it to complete.
