# the list refreshes once, and the timer is on, but every future tick fires into a masked unit
/usr/local/sbin/feedrelay-sync
systemctl enable --now feedrelay-sync.timer >/dev/null 2>&1
