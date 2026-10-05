# truncate through /proc/PID/fd without touching the cause: space is back, then it fills again
pid=$(systemctl show -p MainPID --value cam-poller)
for l in /proc/$pid/fd/*; do
  case "$(readlink "$l")" in *'(deleted)') truncate -s 0 "$l" ;; esac
done
sleep 3
