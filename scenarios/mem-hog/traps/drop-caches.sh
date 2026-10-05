# "clear the memory": page cache is not what is holding it
sync
echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true
sysctl -w vm.swappiness=10 >/dev/null 2>&1 || true
