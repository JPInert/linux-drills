# empty the big log: space is back for now, and it grows again at the same rate
LOG=$(docker inspect event-uploader | grep '"LogPath"' | cut -d'"' -f4)
truncate -s 0 "$LOG"
docker image prune -f
