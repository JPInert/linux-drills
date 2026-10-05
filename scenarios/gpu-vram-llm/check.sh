. /usr/local/lib/drill/lib.sh
st=$(systemctl is-active ollama 2>&1); en=$(systemctl is-enabled ollama 2>&1)
[ "$st" != active ]  && ok "ollama.service is stopped ($st)" || bad "ollama.service is still $st"
[ "$en" != enabled ] && ok "ollama.service will not start at boot ($en)" || bad "ollama.service is still enabled: it comes back at the next reboot"
[ -f /etc/systemd/system/ollama.service ] && [ -x /usr/local/bin/ollama ] \
  && ok "the pilot is still installed (only switched off)" || bad "the ollama unit or binary was removed: the ticket said do not uninstall"
want "analytics.service is active" systemctl is-active --quiet analytics
want "analytics.service is still enabled for next boot" systemctl is-enabled --quiet analytics
pid=$(systemctl show -p MainPID --value analytics 2>/dev/null); pid=${pid:-0}
listed() { [ "$pid" -gt 0 ] && nvidia-smi 2>/dev/null | grep -Eq "^\|[[:space:]]+[0-9]+[[:space:]]+N/A[[:space:]]+N/A[[:space:]]+${pid}[[:space:]]"; }
for _ in 1 2 3 4; do
  listed && break
  age=$(ps -o etimes= -p "$pid" 2>/dev/null | tr -d ' ')
  [ "${age:-99}" -lt 10 ] || break
  sleep 1
done
if listed; then
  ok "nvidia-smi lists the analytics service (pid $pid) on the GPU"
else
  bad "the analytics service (pid $pid) is not on the GPU"
  hb=$(grep -a 'device=' /var/log/analytics/detect.log 2>/dev/null | tail -1 | grep -o 'fps=[0-9.]* device=[a-z0-9:]*')
  [ -n "$hb" ] && info "last analytics heartbeat: $hb"
fi
others=$(nvidia-smi 2>/dev/null | awk -v p="$pid" '/^\|[[:space:]]+0[[:space:]]+N\/A/ && $5 != p {print $5}' | tr '\n' ' ')
[ -z "$others" ] && ok "nothing else holds GPU memory" || bad "other processes still hold GPU memory: pid $others"
finish
