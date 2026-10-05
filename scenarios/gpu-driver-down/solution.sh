set -e
sudo systemctl enable --now nvidia-persistenced
sudo systemctl restart analytics
sleep 2
