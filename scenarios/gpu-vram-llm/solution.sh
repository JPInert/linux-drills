set -e
sudo systemctl disable --now ollama
sudo systemctl restart analytics
sleep 3
