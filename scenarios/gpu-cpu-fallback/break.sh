/usr/local/lib/drill/analytics-install --no-start
# the daemon runs as `analytics` and must be able to publish its GPU state for nvidia-smi to list it
install -d -o analytics -g analytics /run/mock-gpu
# leftover from a bench test on a GPU-less lab unit, copied onto the site box by an imaging script
cat > /etc/default/analytics <<'ENV'
# environment for analytics.service (read via EnvironmentFile=)
OMP_NUM_THREADS=2
TRT_ENGINE_CACHE_ENABLE=1
# 2026-08-19 bench test on the GPU-less lab unit
CUDA_VISIBLE_DEVICES=-1
ENV
# a harmless tuning drop-in, so `systemctl show -p Environment` has something to say that is NOT the culprit
install -d /etc/systemd/system/analytics.service.d
cat > /etc/systemd/system/analytics.service.d/10-tuning.conf <<'UNIT'
[Service]
Environment=CUDA_DEVICE_ORDER=PCI_BUS_ID
UNIT
systemctl daemon-reload
systemctl start analytics
sleep 2
