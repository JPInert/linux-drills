# picks the .dpkg-old backup (not read by the loader)
h=$(grep -n '^WATCHDOG_INTERVAL=' /etc/nvr/conf.d/50-site.conf.dpkg-old | head -1)
echo "file=/etc/nvr/conf.d/50-site.conf.dpkg-old line=$(cut -d: -f1 <<<"$h") value=$(cut -d= -f2 <<<"$h")" > /var/lib/drill/answer
