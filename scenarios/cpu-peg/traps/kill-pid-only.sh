# kill the PID: systemd (Restart=always) brings it straight back under a new PID
kill -9 "$(pgrep -x frame-indexer)"
sleep 4
