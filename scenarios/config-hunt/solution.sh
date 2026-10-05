set -e
cat /etc/nvr/README >/dev/null
last=$(for f in /etc/nvr/nvr.conf /etc/nvr/conf.d/*.conf; do grep -Hn '^WATCHDOG_INTERVAL=' "$f" || true; done | tail -1)
file=$(cut -d: -f1 <<<"$last"); line=$(cut -d: -f2 <<<"$last"); value=$(cut -d= -f2 <<<"$last")
answer "file=$file line=$line value=$value"
