# feeds "work", but from a stray python outside systemd: unit still dead and disabled
setsid nohup python3 /opt/camwatch/camwatch.py >/dev/null 2>&1 &
sleep 1
