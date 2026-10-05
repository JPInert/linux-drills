# works now, gone after a reboot: the manager's runtime environment is not saved
systemctl set-environment https_proxy=http://10.44.0.10:3128
systemctl restart amazon-ssm-agent
sleep 3
