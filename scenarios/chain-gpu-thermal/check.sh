. /usr/local/lib/drill/lib.sh
want "analytics.service is active" systemctl is-active --quiet analytics
pid=$(systemctl show -p MainPID --value analytics 2>/dev/null)
if nvidia-smi 2>/dev/null | grep -Eq "^\|[[:space:]]+0[[:space:]]+N/A[[:space:]]+N/A[[:space:]]+${pid:-x}[[:space:]]"; then
  ok "analytics (pid $pid) is on the GPU"
else
  bad "analytics is not on the GPU"
fi

pl=$(nvidia-smi --query-gpu=power.limit --format=csv,noheader,nounits 2>/dev/null | cut -d. -f1)
[ "${pl:-0}" -ge 70 ] && ok "GPU power limit is the vendor default (${pl} W)" \
  || bad "GPU power limit is ${pl:-?} W (vendor default 70 W): the card is power-capped"
fan=$(python3 -c 'import json;d=json.load(open("/run/mock-gpu/card.state"));print("auto" if d.get("fan_max") is None else d["fan_max"])' 2>/dev/null)
[ "$fan" = auto ] && ok "GPU fan is on the automatic curve" \
  || bad "GPU fan is capped at ${fan}%: the card overheats under load"
reasons=$(nvidia-smi -q -d PERFORMANCE 2>/dev/null | grep -E ': Active$' | grep -v Idle | sed 's/ *:.*//; s/^ *//' | paste -sd, -)
[ -z "$reasons" ] && ok "no clock throttling (Clocks Event Reasons all Not Active)" \
  || bad "the GPU clock is still held back by: $reasons"

# alerts in time: the newest heartbeats run at full frame rate
fps=
for _ in 1 2 3 4 5 6 7; do
  fps=$(grep -a 'INFO  detect: cams=' /var/log/analytics/detect.log 2>/dev/null | tail -1 | grep -o 'fps=[0-9.]*' | cut -d= -f2)
  last=$(stat -c %Y /var/log/analytics/detect.log 2>/dev/null)
  [ -n "$fps" ] && [ "${fps%.*}" -ge 23 ] && [ $(( $(date +%s) - ${last:-0} )) -lt 15 ] && break
  sleep 1
done
[ -n "$fps" ] && [ "${fps%.*}" -ge 23 ] && ok "analytics runs at ${fps} fps (alerts in time)" \
  || bad "analytics runs at ${fps:-?} fps (24 needed): alerts are late"

# after a reboot: would quiet mode put the caps back?
if [ ! -f /usr/local/sbin/gpu-quiet ] || [ ! -f /etc/default/gpu-quiet ] || \
   [ ! -f /etc/systemd/system/gpu-quiet.service ]; then
  bad "the quiet-mode files were deleted: disable it instead, the site may want it back in a quieter form"
fi
st=$(systemctl is-enabled gpu-quiet 2>/dev/null)
case "$st" in
  enabled|enabled-runtime|static|linked*)
    P=$(. /etc/default/gpu-quiet 2>/dev/null; echo "${POWER_LIMIT:-70}")
    F=$(. /etc/default/gpu-quiet 2>/dev/null; echo "${FAN_MAX:-auto}")
    if [ "${P%.*}" -ge 70 ] 2>/dev/null && [ "$F" = auto ]; then
      ok "gpu-quiet still runs at boot, but now applies ${P} W / fan auto"
    else
      bad "gpu-quiet is still $st: at the next boot it sets ${P} W and fan ${F}% again"
    fi ;;
  *) ok "gpu-quiet no longer runs at boot ($st)" ;;
esac
[ -s /var/lib/drill/answer ] && info "your note for the site: $(head -c 120 /var/lib/drill/answer)" \
  || info "bonus: answer \"...\" with what you'd tell the site about the noise complaint"
finish
