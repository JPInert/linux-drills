set -e
cd /var/log/nvr
read -r fails ip < <(grep 'AUTH FAIL' auth.log | grep -o 'ip=[0-9.]*' | sort | uniq -c | sort -rn | head -1)
ip=${ip#ip=}
s5=$(grep '^2026-09-23 02:' access.log | awk '{print $6}' | grep '^5' | wc -l)
read -r n cam < <(awk '{print $6, $5}' access.log | grep '^404 ' | grep -o 'cam/[0-9]*' | sort | uniq -c | sort -rn | head -1)
cam=${cam#cam/}
answer "ip=$ip fails=$fails 5xx=$s5 cam=$cam"
