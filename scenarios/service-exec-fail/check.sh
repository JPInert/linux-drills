. /usr/local/lib/drill/lib.sh
want "feedrelay.service is active" systemctl is-active --quiet feedrelay
body=$(curl -s -m 3 http://127.0.0.1:8091/ || true)
if echo "$body" | grep -q 'feedrelay ok'; then ok ":8091 answers"; else bad ":8091 does not answer"; fi
# the answer must come from the unit's own process, not a copy started by hand
mp=$(systemctl show -p MainPID --value feedrelay 2>/dev/null)
if [ "${mp:-0}" -gt 0 ] && ss -ltnp 'sport = :8091' 2>/dev/null | grep -q "pid=$mp,"; then ok ":8091 is held by the unit's own process (pid $mp)"
else bad ":8091 is not held by feedrelay.service's process (a hand-started copy does not count)"; fi
want "feedrelay.service is still enabled for boot" systemctl is-enabled --quiet feedrelay
m=$(stat -c %a /opt/feedrelay/bin/run.sh 2>/dev/null)
case "$m" in ??[2367]) info "run.sh is world-writable (mode $m): it works, but 755 is the right mode" ;; esac
[ "$(systemctl show -p NeedDaemonReload --value feedrelay)" = yes ] && info "the unit file on disk differs from what systemd has loaded (daemon-reload pending)"
finish
