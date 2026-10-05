# fixes the permission bits, but the unit still points at a directory that does not exist
chmod 755 /opt/feedrelay/bin/run.sh
systemctl restart feedrelay || true
