. /usr/local/lib/drill/lib.sh
FS=/var/log
used() { df -B1 --output=used $FS | tail -1 | tr -d ' '; }

# 1. is the space actually back?
pct=$(df --output=pcent $FS | tail -1 | tr -dc 0-9)
if [ "${pct:-100}" -le 70 ]; then ok "$FS is at ${pct}%"; else bad "$FS is still at ${pct}%"; fi

# 2. any big file that is deleted but still held open under /var/log (that is where the missing space lives)
held=0
for l in /proc/[0-9]*/fd/*; do
  t=$(readlink "$l" 2>/dev/null) || continue
  case $t in
    /var/log/*' (deleted)')
      sz=$(stat -L -c %s "$l" 2>/dev/null || echo 0)
      if [ "$sz" -gt 1000000 ]; then
        pid=${l#/proc/}; pid=${pid%%/*}
        bad "pid $pid ($(cat /proc/$pid/comm 2>/dev/null)) still holds a deleted ${t% (deleted)} of $((sz / 1000000)) MB: the space is not freed until it lets go"
        held=1
      fi ;;
  esac
done
[ $held = 0 ] && ok "no big deleted-but-open file is left under $FS"

# 3. the poller has to be running, not stopped to make the problem go away
want "cam-poller.service must be active" systemctl is-active --quiet cam-poller

# 4. and it must not be filling the disk again
a=$(used); sleep 3; b=$(used)
g=$(( (b - a) / 3 ))
if [ "$g" -lt 20000 ]; then ok "$FS grows ${g} B/s (quiet)"; else bad "$FS is still growing $((g / 1000)) KB/s: you freed the space but not the cause"; fi

[ -f /etc/logrotate.d/cam-poller ] && info "logrotate rule present (bonus)" || info "bonus: no /etc/logrotate.d/cam-poller rule for the poll log"
finish
