# right file, but systemd never re-read it before the restart
mkdir -p /etc/systemd/system/amazon-ssm-agent.service.d
printf '[Service]\nEnvironment=https_proxy=http://10.44.0.10:3128\n' \
  > /etc/systemd/system/amazon-ssm-agent.service.d/proxy.conf
systemctl restart amazon-ssm-agent
sleep 3
