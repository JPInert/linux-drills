. /usr/local/lib/drill/lib.sh
LIMIT_KB=153600     # 150 MB: nothing on this box legitimately needs more than ~50 MB

# biggest resident process on the box, by VmRSS (this is what top's RES / ps' RSS report)
max=0; who=; wpid=
for d in /proc/[0-9]*; do
  r=$(awk '/^VmRSS:/{print $2}' $d/status 2>/dev/null)
  [ -n "$r" ] || continue
  if [ "$r" -gt "$max" ]; then max=$r; who=$(cat $d/comm 2>/dev/null); wpid=${d#/proc/}; fi
done
if [ "$max" -gt "$LIMIT_KB" ]; then bad "$who (pid $wpid) still holds $((max / 1024)) MB resident"
else ok "no process holds more than $((max / 1024)) MB resident (largest: $who)"; fi

want "analytics.service must still be active" systemctl is-active --quiet analytics
want "videoproc.service must still be active" systemctl is-active --quiet videoproc
# stopping it, or restarting it with a sane buffer, are both fine: the RSS check above decides
st=$(systemctl is-active motion-buffer 2>/dev/null)
if [ "$st" = active ] && [ "$max" -le "$LIMIT_KB" ]; then info "motion-buffer is running again but small ($(grep '^PREROLL_MB' /etc/motion-buffer.conf)): acceptable"; fi
finish
