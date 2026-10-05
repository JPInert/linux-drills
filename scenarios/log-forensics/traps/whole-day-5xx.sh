. /var/lib/drill/.expected
n=$(awk '$1=="2026-09-23" && $6 ~ /^5/' /var/log/nvr/access.log | wc -l)
echo "ip=$EXP_IP fails=$EXP_FAILS 5xx=$n cam=$EXP_CAM" > /var/lib/drill/answer
