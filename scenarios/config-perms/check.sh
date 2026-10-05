. /usr/local/lib/drill/lib.sh
CONF=/etc/analytics/analytics.conf
DIR=/etc/analytics

# 1. the service must come up AND stay up: a flapping unit is "active" for ~50 ms every cycle,
#    so require the same MainPID to still be active a few seconds later.
up=0
for i in $(seq 1 12); do
  if [ "$(systemctl is-active analytics 2>/dev/null)" = active ]; then up=1; break; fi
  sleep 0.5
done
pid=; stable=0
if [ $up = 1 ]; then
  pid=$(systemctl show -p MainPID --value analytics)
  sleep 3.5
  if [ "$(systemctl is-active analytics 2>/dev/null)" = active ] && [ "$(systemctl show -p MainPID --value analytics)" = "$pid" ] && [ "${pid:-0}" != 0 ]; then stable=1; fi
fi
if [ $stable = 1 ]; then ok "analytics.service is up and stable (pid $pid)"
else bad "analytics.service is not staying up: $(systemctl is-active analytics 2>/dev/null) ($(systemctl show -p Result --value analytics 2>/dev/null))"; fi

# 2. it must run as its own user, not as root
if [ $stable = 1 ]; then
  u=$(ps -o user= -p "$pid" 2>/dev/null | tr -d ' ')
  if [ "$u" = analytics ]; then ok "it runs as user analytics"; else bad "analytics is running as '$u', not as the analytics user"; fi
fi

# 3. the password must not be exposed: no world bits on the file, no world write on its directory
if [ -f $CONF ]; then
  m=$(stat -c %a $CONF); o=${m: -1}
  if [ $(( o & 7 )) -eq 0 ]; then ok "config mode $m: nothing for 'other'"; else bad "config mode is $m: 'other' can still read or write the camera password"; fi
  grep -q '^RTSP_PASSWORD=' $CONF && ok "config still holds the camera login" || bad "the camera login is gone from the config"
else bad "$CONF is missing"; fi
dm=$(stat -c %a $DIR 2>/dev/null); do=${dm: -1}
if [ $(( do & 2 )) -eq 0 ]; then ok "$DIR mode $dm: not world-writable"; else bad "$DIR is world-writable ($dm)"; fi
if [ "$(stat -c %U $CONF 2>/dev/null)" = root ]; then info "config is root-owned (best practice: the service cannot rewrite its own config)"; fi
finish
