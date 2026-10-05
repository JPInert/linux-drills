set -e
cd /usr/local/cuda/lib64
sudo ln -sf libcudart.so.12.2.140 libcudart.so.12
sudo ldconfig
sudo systemctl restart analytics
sleep 2
