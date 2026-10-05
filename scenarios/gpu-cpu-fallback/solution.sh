set -e
sudo sed -i '/^CUDA_VISIBLE_DEVICES=/d' /etc/default/analytics
sudo systemctl restart analytics
sleep 2
