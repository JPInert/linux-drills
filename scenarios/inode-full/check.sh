. /usr/local/lib/drill/lib.sh
D=/var/spool/frames
KEEP_MIN=190          # of the 200 files from the last 20 h that were there at the start

# 1. inodes, not blocks
ip=$(df --output=ipcent $D | tail -1 | tr -dc 0-9)
if [ "${ip:-100}" -lt 80 ]; then ok "inode use on $D is ${ip}%"; else bad "inode use on $D is still ${ip}%"; fi

# 2. can something new actually be created?
probe=$D/.probe.$$
if err=$(touch "$probe" 2>&1); then rm -f "$probe"; ok "a new file can be created in $D"
else bad "cannot create a file in $D: ${err##*: }"; fi

# 3. the last day of frames must have survived (files that existed at the start, newer than ~20 h)
t0=$(cat /var/lib/drill/inode-full.t0 2>/dev/null || echo 0)
keep=$(find $D -type f -newermt "@$((t0 - 73000))" ! -newermt "@$t0" 2>/dev/null | wc -l)
if [ "$keep" -ge "$KEEP_MIN" ]; then ok "the last 24 h of frames are intact ($keep files)"
else bad "only $keep of the ~200 frames from the last 24 h are left: the incident-review data was deleted"; fi

# 4. the grabber must be up and actually writing again (not stopped to make the error go away)
want "frame-grabber.service must be active" systemctl is-active --quiet frame-grabber
ref=$(mktemp /run/inode-full-ref.XXXXXX); sleep 2.5
n=$(find $D -type f -newer "$ref" 2>/dev/null | wc -l); rm -f "$ref"
if [ "$n" -ge 1 ]; then ok "frame-grabber wrote $n new frame(s) during the check"; else bad "frame-grabber is not writing new frames"; fi

# bonus, not required: something that stops this happening again
if grep -rlE 'var/spool/frames' /etc/cron.d /etc/cron.daily /etc/cron.hourly /etc/tmpfiles.d /etc/systemd/system /etc/logrotate.d 2>/dev/null | grep -q .; then
  info "a retention rule for /var/spool/frames exists (bonus)"; else info "bonus: nothing prevents a repeat (no retention job for /var/spool/frames)"; fi
finish
