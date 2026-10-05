set -e
sudo systemctl start feedrelay-sync || true
sudo systemctl unmask feedrelay-sync.service
sudo systemctl start feedrelay-sync.service
sudo systemctl enable --now feedrelay-sync.timer
systemctl list-timers feedrelay-sync.timer --no-pager
cat /var/lib/feedrelay/last-sync
