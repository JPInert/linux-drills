set -e
df -h /var/spool/frames                                  # plenty of blocks free...
df -i /var/spool/frames                                  # ...but IFree is 0
sudo du --inodes /var/spool/frames
sudo find /var/spool/frames -type f -mtime +3 | wc -l    # how many would go?
sudo find /var/spool/frames -mtime +3 -delete            # by age: the last day survives
df -i /var/spool/frames
# stop it coming back: a nightly retention job
sudo tee /etc/systemd/system/frames-retention.service >/dev/null <<'UNIT'
[Unit]
Description=Delete camera thumbnails older than 3 days

[Service]
Type=oneshot
ExecStart=/usr/bin/find /var/spool/frames -mindepth 1 -mtime +3 -delete
UNIT
sudo tee /etc/systemd/system/frames-retention.timer >/dev/null <<'UNIT'
[Unit]
Description=Nightly thumbnail retention

[Timer]
OnCalendar=daily
Persistent=true

[Install]
WantedBy=timers.target
UNIT
sudo systemctl daemon-reload
sudo systemctl enable --now frames-retention.timer
sleep 3
systemctl is-active frame-grabber
