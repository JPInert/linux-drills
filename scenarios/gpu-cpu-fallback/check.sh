. /usr/local/lib/drill/lib.sh
want "analytics.service is active" systemctl is-active --quiet analytics
want "analytics.service is still enabled for next boot" systemctl is-enabled --quiet analytics
pid=$(systemctl show -p MainPID --value analytics 2>/dev/null); pid=${pid:-0}
listed() { [ "$pid" -gt 0 ] && nvidia-smi 2>/dev/null | grep -Eq "^\|[[:space:]]+[0-9]+[[:space:]]+N/A[[:space:]]+N/A[[:space:]]+${pid}[[:space:]]"; }
# a just-restarted daemon publishes its GPU state within a moment: give it a few seconds
for _ in 1 2 3 4; do
  listed && break
  age=$(ps -o etimes= -p "$pid" 2>/dev/null | tr -d ' ')
  [ "${age:-99}" -lt 10 ] || break
  sleep 1
done
if listed; then
  ok "nvidia-smi lists the analytics service (pid $pid) using the GPU"
else
  bad "nvidia-smi does not list the analytics service (GPU shows: $(nvidia-smi --query-gpu=utilization.gpu,memory.used --format=csv,noheader 2>/dev/null))"
  hb=$(grep -a 'device=' /var/log/analytics/detect.log 2>/dev/null | tail -1 | grep -o 'fps=[0-9.]* device=[a-z0-9:]*')
  [ -n "$hb" ] && info "last analytics heartbeat: $hb"
fi
finish
