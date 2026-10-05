# persistent drop-in, wrong variable: https:// URLs only use https_proxy
mkdir -p /etc/systemd/system/amazon-ssm-agent.service.d
printf '[Service]\nEnvironment=http_proxy=http://10.44.0.10:3128\n' \
  > /etc/systemd/system/amazon-ssm-agent.service.d/proxy.conf
systemctl daemon-reload
systemctl restart amazon-ssm-agent
sleep 3
