# wait until systemd is fully up (the harness can race a busy host)
for i in $(seq 1 120); do case $(systemctl is-system-running 2>/dev/null) in running|degraded) break ;; esac; sleep 0.5; done
install -d /var/lib/feedrelay
cat > /usr/local/sbin/feedrelay-sync <<'SH'
#!/bin/bash
# feedrelay-sync: refresh the NVR's camera definitions (stand-in)
set -e
install -d /var/lib/feedrelay
date -u +%Y-%m-%dT%H:%M:%SZ > /var/lib/feedrelay/last-sync
echo "feedrelay-sync: 4 camera definitions synced"
SH
chmod 0755 /usr/local/sbin/feedrelay-sync
# vendor units, as the package installs them
cat > /usr/lib/systemd/system/feedrelay-sync.service <<'UNIT'
[Unit]
Description=Feed relay: refresh camera definitions on the NVR

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/feedrelay-sync
UNIT
cat > /usr/lib/systemd/system/feedrelay-sync.timer <<'UNIT'
[Unit]
Description=Feed relay: camera definition sync every 15 minutes

[Timer]
OnCalendar=*:0/15

[Install]
WantedBy=timers.target
UNIT
systemctl daemon-reload
# the last good sync was last week
echo 2026-09-19T03:15:02Z > /var/lib/feedrelay/last-sync
touch -d '2026-09-19 03:15:02' /var/lib/feedrelay/last-sync
# Monday's troubleshooting: "stop it overwriting the hand-edited camera list", and never undone
systemctl mask feedrelay-sync.service >/dev/null 2>&1
touch /var/lib/drill/unit-masked.t0
[ "$(systemctl show -p LoadState --value feedrelay-sync.service)" = masked ]
sleep 1
