# "just deprioritise it": it still burns a whole core when nothing else wants the CPU
renice -n 19 -p "$(pgrep -x frame-indexer)" >/dev/null
sleep 1
