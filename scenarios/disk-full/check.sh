. /usr/local/lib/drill/lib.sh
LOG=/var/log/analytics/detect.log
pct=$(df --output=pcent /var/log | tail -1 | tr -dc 0-9)
if [ "${pct:-100}" -le 70 ]; then ok "/var/log is at ${pct}%"; else
  bad "/var/log is still at ${pct}%"
  if ls -l /proc/[0-9]*/fd 2>/dev/null | grep -q 'detect.log (deleted)'; then
    bad "a process still holds a DELETED copy of detect.log (space is not freed until it lets go)"; fi
fi
want "analytics.service is active" systemctl is-active --quiet analytics
if [ -f $LOG ]; then
  a=$(stat -c %s $LOG); sleep 3; b=$(stat -c %s $LOG)
  g=$(( (b - a) / 3 ))
  if [ "$g" -lt 20000 ]; then ok "detect.log grows ${g} B/s (quiet)"; else bad "detect.log is still growing ${g} B/s: you emptied it but not the cause"; fi
else bad "$LOG is missing (service should be writing it)"; fi
[ -f /etc/logrotate.d/analytics ] && info "logrotate rule present (bonus)" || info "bonus: no /etc/logrotate.d/analytics rule for the detect log"
finish
