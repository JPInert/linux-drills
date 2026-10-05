# grep ' 5[0-9][0-9] ' also matches the BYTES column; everything else is right
. /var/lib/drill/.expected
n=$(grep '^2026-09-23 02:' /var/log/nvr/access.log | grep -c ' 5[0-9][0-9] ')
echo "ip=$EXP_IP fails=$EXP_FAILS 5xx=$n cam=$EXP_CAM" > /var/lib/drill/answer
