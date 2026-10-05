. /usr/local/lib/drill/lib.sh
NAME=frame-indexer
HZ=$(getconf CLK_TCK)

# utime+stime (clock ticks) of one pid, empty if it is gone.  The comm field may contain spaces,
# so cut everything up to the LAST ')' before splitting.
ticks() { local s; s=$(cat /proc/$1/stat 2>/dev/null) || return 1; s=${s##*) }; set -- $s; echo $(( ${12} + ${13} )); }

state=$(systemctl is-active $NAME 2>/dev/null)
case $state in
  activating|reloading) bad "$NAME.service is in '$state': systemd keeps bringing it back" ;;
esac

pids0=$(pgrep -x $NAME | sort -n | tr '\n' ' ')
declare -A t0
for p in $pids0; do t0[$p]=$(ticks $p); done
sleep 3
pids1=$(pgrep -x $NAME | sort -n | tr '\n' ' ')

if [ -z "$pids0$pids1" ]; then
  ok "no $NAME process is running (service is $state)"
else
  for p in $pids1; do
    if [ -n "${t0[$p]:-}" ]; then
      t1=$(ticks $p) || continue
      pct=$(( (t1 - ${t0[$p]}) * 100 / (3 * HZ) ))
    else
      # not there 3 s ago: it was (re)spawned during the sample; use its whole life
      up=$(cut -d' ' -f1 /proc/uptime | cut -d. -f1)
      st=$(s=$(cat /proc/$p/stat 2>/dev/null); s=${s##*) }; set -- $s; echo ${20})
      life=$(( up - st / HZ )); [ "$life" -lt 1 ] && life=1
      pct=$(( $(ticks $p) * 100 / (life * HZ) ))
      bad "$NAME pid $p appeared during the check: something respawned it"
    fi
    pst=$(awk '/^State:/{print $2}' /proc/$p/status 2>/dev/null)
    if [ "$pst" = T ]; then bad "$NAME pid $p is only suspended (state T), not fixed"
    elif [ "${pct:-0}" -gt 30 ]; then bad "$NAME pid $p is using ${pct}% CPU (limit 30%)"
    else ok "$NAME pid $p is using ${pct}% CPU"; fi
  done
  for p in $pids0; do
    case " $pids1" in *" $p "*) ;; *) [ -n "$pids1" ] && bad "$NAME pid $p was killed and replaced: it is respawning" ;; esac
  done
fi

# the legitimate residents must all still be up: no "killed everything" shortcut
for u in videoproc nvr-web analytics; do want "$u.service must still be active" systemctl is-active --quiet $u; done
if [ "$state" = active ]; then :; elif systemctl is-enabled --quiet $NAME 2>/dev/null; then
  info "$NAME stopped, still enabled: note in the ticket that it returns at reboot until the owner fixes it"; fi
finish
