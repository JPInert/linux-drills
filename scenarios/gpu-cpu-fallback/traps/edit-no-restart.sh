# right edit, but the running process keeps the environment it was started with
sed -i '/^CUDA_VISIBLE_DEVICES=/d' /etc/default/analytics
