# fixes the file but not the 0700 directory above it: still Permission denied
chgrp analytics /etc/analytics/analytics.conf
chmod 640 /etc/analytics/analytics.conf
systemctl restart analytics; sleep 4
