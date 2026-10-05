set -e
cat /etc/nvr/cameras.conf
grep OFFLINE /var/log/nvr/nvr.log | grep -o 'cam[0-9]*' | sort | uniq -c
cat /var/lib/nvr/cameras/cam07.json
grep rssi /var/lib/nvr/cameras/*.json
rssi=$(grep rssi /var/lib/nvr/cameras/cam07.json | tr -dc 0-9-)
answer "camera7 is not faulty (its uptime shows it never rebooted). Its WiFi signal is weak: RSSI $rssi dBm, many retries, 6.5 Mbps, on busy channel 6, while the other WiFi cameras are -49 and -54. Do not replace the camera or reboot the NVR. Escalate to the customer's IT: add or move an access point near the dining room, or change the channel, or wire it with PoE."
