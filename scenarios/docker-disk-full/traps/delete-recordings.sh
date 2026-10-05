# the site lead's theory: delete old footage (a different disk, not the full one)
find /srv/nvr/recordings -type f -mtime +2 -delete
docker image prune -f
