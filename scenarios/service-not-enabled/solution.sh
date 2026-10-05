set -e
sudo systemctl enable --now camwatch
sleep 1
curl -fs -m 3 http://localhost:8090/ | grep -q 'camwatch relay'
