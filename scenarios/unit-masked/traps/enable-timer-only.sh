# the schedule is switched on, but every tick fires into a masked service and the list stays stale
systemctl enable --now feedrelay-sync.timer >/dev/null 2>&1
