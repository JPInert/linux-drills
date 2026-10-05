set -e
pid=$(sudo ss -tlnp | grep 8080 | grep -o 'pid=[0-9]*' | head -1 | cut -d= -f2)
[ -n "$pid" ]
sudo kill "$pid"; sleep 1
if [ -d "/proc/$pid" ]; then sudo kill -9 "$pid"; sleep 1; fi
sudo systemctl start dashboard
sleep 1
