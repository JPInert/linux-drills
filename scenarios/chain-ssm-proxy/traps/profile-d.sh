# proxy put where only login shells read it: a service never sources profile.d
printf 'export https_proxy=http://10.44.0.10:3128\nexport HTTPS_PROXY=http://10.44.0.10:3128\n' \
  > /etc/profile.d/ssm-proxy.sh
systemctl restart amazon-ssm-agent
sleep 2
