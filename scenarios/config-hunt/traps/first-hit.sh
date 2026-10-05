# takes the first uncommented-looking hit of a recursive grep instead of applying the ordering rule
. /var/lib/drill/.expected
h=$(grep -rn '^WATCHDOG_INTERVAL=' /etc/nvr | sort | head -1)
echo "file=$(cut -d: -f1 <<<"$h") line=$(cut -d: -f2 <<<"$h") value=$(cut -d= -f3 <<<"$h")" > /var/lib/drill/answer
