# `systemctl edit --runtime` writes under /run, which is wiped at boot
mkdir -p /run/systemd/system/amazon-ssm-agent.service.d
printf '[Service]\nEnvironment=https_proxy=http://10.44.0.10:3128\n' \
  > /run/systemd/system/amazon-ssm-agent.service.d/override.conf
systemctl daemon-reload
systemctl restart amazon-ssm-agent
sleep 3
