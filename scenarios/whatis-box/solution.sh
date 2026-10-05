set -e
nvidia-smi
gpu=$(nvidia-smi -L | grep -o 'RTX [A-Z0-9]*' | cut -d' ' -f2)
systemctl list-units --type=service | grep running
failed=$(systemctl list-units --failed --plain --no-legend --type=service | cut -d' ' -f1 | head -1)
sudo ss -tlnp
web=$(sudo ss -tlnp | grep nvr-web | grep -o ':[0-9]* ' | head -1 | tr -dc 0-9)
sudo grep -E '^(CAMERAS|MODEL)=' /etc/analytics/analytics.conf
cams=$(sudo grep '^CAMERAS=' /etc/analytics/analytics.conf | cut -d= -f2)
model=$(sudo grep '^MODEL=' /etc/analytics/analytics.conf | cut -d= -f2)
ls -l /opt/analytics/models
answer "gpu=$gpu vram=12288 cams=$cams web=$web failed=${failed%.service} model=${model##*/}"
