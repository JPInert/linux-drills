# baseline: a deployed box (analytics + the usual residents)
/usr/local/lib/drill/analytics-install
/usr/local/lib/drill/lived-in
python3 - <<'PY'
import json, os, random, time
r = random.Random(os.urandom(16))
os.makedirs("/etc/nvr", exist_ok=True)
os.makedirs("/var/lib/nvr/cameras", exist_ok=True)
os.makedirs("/var/log/nvr", exist_ok=True)
cams = [("cam01", "Front Entrance", "wired"), ("cam02", "Lobby", "wired"),
        ("cam03", "Hall North", "wired"), ("cam04", "Hall South", "wired"),
        ("cam05", "Activity Room", "wired"), ("cam06", "Courtyard", "wifi"),
        ("cam07", "Dining Room", "wifi"), ("cam08", "Library", "wifi")]
with open("/etc/nvr/cameras.conf", "w") as f:
    f.write("# NVR camera list: id  ip  link  location\n")
    for i, (c, n, l) in enumerate(cams, 1):
        f.write("%s  10.50.1.%d  %-5s  %s\n" % (c, 30 + i, l, n))
now = time.time()
# the camera's own status API, as the NVR last polled it (one key per line, like the API returns it)
wifi = {"cam06": dict(rssi=-54, noise=-92, rate=86.7, retry=3, ch=11, nb=3, rc=0),
        "cam07": dict(rssi=r.choice([-79, -80, -81, -82, -83]), noise=-89, rate=6.5,
                      retry=r.randint(35, 48), ch=6, nb=r.randint(12, 17), rc=0),
        "cam08": dict(rssi=-49, noise=-93, rate=144.4, retry=2, ch=1, nb=2, rc=0)}
for i, (c, n, l) in enumerate(cams, 1):
    d = {"camera": c, "name": n, "ip": "10.50.1.%d" % (30 + i), "model": "IPC-B340W" if l == "wifi" else "IPC-B340",
         "firmware": "2.1.3", "firmware_update_available": "2.1.4" if c in ("cam03", "cam07") else "",
         "uptime_s": r.randint(330000, 900000), "link": l}   # > 3 days: every camera outlived the whole log
    if l == "wired":
        d.update({"eth_speed_mbps": 100, "eth_duplex": "full", "eth_errors": 0})
    else:
        w = wifi[c]
        d.update({"ssid": "HR-IoT", "band": "2.4GHz", "channel": w["ch"], "rssi_dbm": w["rssi"],
                  "noise_dbm": w["noise"], "tx_rate_mbps": w["rate"], "tx_retries_pct": w["retry"],
                  "neighbor_aps_same_channel": w["nb"]})
    d["polled"] = time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(now - r.randint(5, 55)))
    with open("/var/lib/nvr/cameras/%s.json" % c, "w") as f:
        json.dump(d, f, indent=2); f.write("\n")
# the NVR log: 3 days of routine lines, camera7 dropping around meal times, one old cam03 blip
ev = []
t0 = now - 3 * 86400
t = t0
while t < now:
    for c, n, l in cams:
        if r.random() < 0.9:
            ev.append((t + r.uniform(0, 60), "INFO ", "rec %s: segment closed, 900 s, %d MB" % (c, r.randint(180, 260))))
    t += 900
for day in range(4):
    base = time.mktime(time.localtime(t0 + day * 86400)[:3] + (0, 0, 0, 0, 0, -1))
    for h0, h1, n in ((7, 9, 4), (11.5, 13.5, 4), (17, 19, 5), (0, 24, 2)):
        for _ in range(n):
            s = base + r.uniform(h0, h1) * 3600
            if s < t0 or s > now - 300:
                continue
            gap = r.randint(55, 150)
            ev.append((s, "WARN ", "stream cam07 (Dining Room): no frames for 10 s, marking OFFLINE"))
            ev.append((s + 10, "WARN ", "stream cam07: RTSP connect 10.50.1.37:554 timed out, retrying"))
            ev.append((s + gap, "INFO ", "stream cam07: reconnected after %d s" % gap))
s = t0 + r.uniform(3, 6) * 3600
ev.append((s, "WARN ", "stream cam03 (Hall North): no frames for 10 s, marking OFFLINE"))
ev.append((s + 22, "INFO ", "stream cam03: reconnected after 22 s"))
ev.append((t0 + 7200, "ERROR", "rec cam03: segment write slow (1840 ms), disk busy"))
ev.append((t0 + 40000, "INFO ", "firmware check: update 2.1.4 available for cam03 cam07 (not applied)"))
ev.sort()
with open("/var/log/nvr/nvr.log", "w") as f:
    for ts, lvl, msg in ev:
        f.write("%s %s nvr: %s\n" % (time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(ts)), lvl, msg))
PY
chmod -R a+rX /etc/nvr /var/lib/nvr /var/log/nvr
