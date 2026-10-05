. /usr/local/lib/drill/lib.sh
ls=$(systemctl show -p LoadState --value feedrelay-sync.service 2>/dev/null)
if [ "$ls" = loaded ]; then ok "feedrelay-sync.service can be started (LoadState=$ls)"
else bad "feedrelay-sync.service cannot run: LoadState=${ls:-unknown}"; fi
if [ /var/lib/feedrelay/last-sync -nt /var/lib/drill/unit-masked.t0 ]; then ok "a sync has run since the box was broken ($(cat /var/lib/feedrelay/last-sync))"
else bad "the camera list is still stale: last sync $(cat /var/lib/feedrelay/last-sync 2>/dev/null || echo never)"; fi
want "feedrelay-sync.timer is enabled (comes back after a reboot)" systemctl is-enabled --quiet feedrelay-sync.timer
want "feedrelay-sync.timer is active (the 15-minute schedule is running)" systemctl is-active --quiet feedrelay-sync.timer
finish
