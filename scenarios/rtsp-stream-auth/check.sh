. /usr/local/lib/drill/lib.sh
shopt -s extglob
CONF=/etc/stream-ingest/ingest.conf
want "stream-ingest.service is active" systemctl is-active --quiet stream-ingest
want "stream-ingest.service is enabled for next boot" systemctl is-enabled --quiet stream-ingest
perm=$(stat -c '%U:%G %a' "$CONF" 2>/dev/null)
case $perm in
  "root:ingest 640"|"root:ingest 440") ok "config is $perm (only root and the ingest group can read the password)" ;;
  *) bad "config $CONF is '${perm:-missing}' (it holds a camera password: owner root, group ingest, no access for others)" ;;
esac
# the effect: what THIS run of the service (its current PID) got back from camera1 in the last few polls
pid=$(systemctl show -p MainPID --value stream-ingest 2>/dev/null); pid=${pid:-0}
lines() { [ "$pid" -gt 0 ] && journalctl -q -o cat _SYSTEMD_UNIT=stream-ingest.service _PID="$pid" --since "-12s" 2>/dev/null | grep 'DESCRIBE'; }
for _ in 1 2 3 4 5 6 7 8; do
  last=$(lines | tail -1)
  case $last in *" 200 OK"*) break ;; esac
  sleep 1
done
url='rtsp://10.50.1.31:554/Streaming/Channels/101'
case $last in
  "") bad "the running service (pid $pid) logged no DESCRIBE in the last 12 s" ;;
  *"DESCRIBE rtsp://10.50.1.31"?(:554)"/Streaming/Channels/101 -> RTSP/1.0 200 OK"*)
     ok "the service's latest DESCRIBE of camera1's main stream got 200 OK" ;;
  *"DESCRIBE rtsp://10.50.1.31"?(:554)"/Streaming/Channels/101 "*) bad "the service's latest DESCRIBE: ${last#*-> }" ;;
  *) bad "the service is not asking camera1's main stream ($url): ${last#*: }" ;;
esac
finish
