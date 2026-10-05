# chain-gpu-thermal: last month a "quiet mode" unit was added for a noise
# complaint (closet next to the attendants' break room): at boot it caps the GPU at
# 40 W and its fan at 25 %. Mornings are cool enough; in the afternoon the card
# hits 87 C, thermal-throttles on top of the power cap, and inference falls
# behind: alerts arrive seconds late. The fix restores the vendor power limit
# and fan curve persistently (the noise goes back to the site as a facilities
# issue, it is not solved by strangling the GPU).
/usr/local/lib/drill/lived-in >/dev/null 2>&1
/usr/local/lib/drill/analytics-install --no-start

install -m 0755 /drill/mock/gpu-fan /usr/local/bin/gpu-fan
cat > /etc/default/gpu-quiet <<'CONF'
# GPU quiet mode for the server closet next to the attendants' break room.
# Added 2026-08-19, site ticket HR-4471 ("fan noise during night shift").
# Watts (vendor default 70) and fan cap in percent (auto = driver curve).
POWER_LIMIT=40
FAN_MAX=25
CONF
cat > /usr/local/sbin/gpu-quiet <<'SH'
#!/bin/bash
# apply GPU quiet mode from /etc/default/gpu-quiet (run by gpu-quiet.service)
set -e
nvidia-smi -pm 1
nvidia-smi -pl "${POWER_LIMIT:-70}"
if [ "${FAN_MAX:-auto}" = auto ]; then gpu-fan --auto; else gpu-fan --max "$FAN_MAX"; fi
SH
chmod 0755 /usr/local/sbin/gpu-quiet
cat > /etc/systemd/system/gpu-quiet.service <<'UNIT'
[Unit]
Description=GPU quiet mode (power and fan cap)
After=nvidia-persistenced.service

[Service]
Type=oneshot
RemainAfterExit=yes
EnvironmentFile=/etc/default/gpu-quiet
ExecStart=/usr/local/sbin/gpu-quiet

[Install]
WantedBy=multi-user.target
UNIT
touch -d '2026-08-19 14:20' /etc/default/gpu-quiet /usr/local/sbin/gpu-quiet \
  /etc/systemd/system/gpu-quiet.service

# the red herring: one old Xid from a driver update 40 days ago, long gone
install -d /var/log
{
  d=$(date -d '40 days ago' '+%b %e %H:%M:%S')
  echo "$d edge-nvr-03 kernel: [  412.883120] NVRM: Xid (PCI:0000:01:00): 13, pid=2231, name=python3, Graphics SM Warp Exception on (GPC 0, TPC 1, SM 0): Out Of Range Address"
  echo "$d edge-nvr-03 kernel: [  412.883201] NVRM: Xid (PCI:0000:01:00): 13, pid=2231, name=python3, Graphics Exception: ESR 0x504648=0x102000e 0x504650=0x20 0x504644=0xd3eff2 0x50464c=0x7f"
} > /var/log/kern.log.1
chown root:adm /var/log/kern.log.1; chmod 0640 /var/log/kern.log.1
touch -d '40 days ago' /var/log/kern.log.1

# three days of detect.log: fine every morning, behind every afternoon
install -d -o analytics -g analytics /var/log/analytics
python3 - <<'PY'
import time, datetime as dt
L = []
now = time.time()
fr = 0
t = now - 3 * 86400
while t < now - 60:
    h = time.localtime(t).tm_hour
    hot = 13 <= h < 19
    s = time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(t))
    if hot:
        fps = 13.9 if 14 <= h < 18 else 17.8
        fr += int(fps * 600)
        L.append("%s INFO  detect: cams=4 fps=%.1f device=cuda:0 frames=%d sm_clock=%dMHz"
                 % (s, fps, fr, 1050 if fps < 15 else 1350))
        L.append("%s WARN  detect: inference behind real time (%.1f fps < 24): alert latency "
                 "%.1fs over SLO 2.0s" % (s, fps, 24.0 / fps * 1.9))
    else:
        fr += 24 * 600
        L.append("%s INFO  detect: cams=4 fps=24.0 device=cuda:0 frames=%d sm_clock=1770MHz"
                 % (s, fr))
    t += 600
open("/var/log/analytics/detect.log", "w").write("\n".join(L) + "\n")
PY
chown analytics:analytics /var/log/analytics/detect.log

systemctl daemon-reload
systemctl enable gpu-quiet.service >/dev/null 2>&1
systemctl start gpu-quiet.service
systemctl start analytics
for _ in $(seq 1 40); do [ -f /run/mock-gpu/analytics.json ] && break; sleep 0.25; done
[ -f /run/mock-gpu/analytics.json ]
nvidia-smi --query-gpu=power.limit --format=csv,noheader | grep -q '^40.00 W'
