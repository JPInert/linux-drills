set -e
sudo journalctl -u analytics -n 5 || true
ls -l /etc/analytics/analytics.conf || true               # tech itself is denied: the directory is closed too
sudo ls -l /etc/analytics; sudo ls -l /etc/analytics/analytics.conf
id analytics
sudo -u analytics head -1 /etc/analytics/analytics.conf || true   # reproduce the failure as the service user
namei -l /etc/analytics/analytics.conf || true                    # every directory on the path, with modes
# least privilege: root owns it, the service's group may read it, nobody else
sudo chgrp analytics /etc/analytics/analytics.conf
sudo chmod 640 /etc/analytics/analytics.conf
sudo chmod 755 /etc/analytics
sudo systemctl restart analytics
sleep 2
systemctl is-active analytics
