# "clear docker's disk": every image, container and log gone
systemctl stop docker
rm -rf /var/lib/docker/*
systemctl start docker
sleep 2
