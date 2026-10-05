# feeds come back from a hand-started copy; the unit stays failed
setsid nohup bash /opt/feedrelay/bin/run.sh >/dev/null 2>&1 &
sleep 1
