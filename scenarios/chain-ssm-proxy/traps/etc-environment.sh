# add it to /etc/environment "again", plus in the agent's /etc/default file
# that its unit never loads
printf 'https_proxy="http://10.44.0.10:3128"\n' >> /etc/environment
printf 'https_proxy=http://10.44.0.10:3128\n' > /etc/default/amazon-ssm-agent
systemctl restart amazon-ssm-agent
sleep 2
