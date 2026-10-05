# fix the red herring: the failed firmware refresh has nothing to do with SSM
systemctl reset-failed fwupd-refresh.service
systemctl restart amazon-ssm-agent
sleep 2
