/usr/local/lib/drill/analytics-install
/usr/local/lib/drill/lived-in
python3 - <<'PY'
import os, random, time
r = random.Random(os.urandom(16))
for d in ("/etc/nvr", "/var/log/nvr", "/var/log/remote"):
    os.makedirs(d, exist_ok=True)
cams = [("cam01", "Front Entrance", "sw-1f", "Gi1/0/1"), ("cam02", "Lobby", "sw-1f", "Gi1/0/2"),
        ("cam03", "Dining Room", "sw-1f", "Gi1/0/3"), ("cam04", "Activity Room", "sw-1f", "Gi1/0/4"),
        ("cam05", "2F Hall East", "sw-2f", "Gi1/0/5"), ("cam06", "2F Hall West", "sw-2f", "Gi1/0/6"),
        ("cam07", "2F Pay Station", "sw-2f", "Gi1/0/7"), ("cam08", "2F Stairs", "sw-2f", "Gi1/0/8")]
with open("/etc/nvr/cameras.conf", "w") as f:
    f.write("# NVR camera list: id  ip  switch  port  location\n")
    for i, (c, n, sw, p) in enumerate(cams, 1):
        f.write("%s  10.50.1.%d  %s  %s  %s\n" % (c, 30 + i, sw, p, n))
now = time.time()
t0 = now - 3 * 86400
nvr, sw2, sw1 = [], [], []
def at(day, hours):
    b = time.mktime(time.localtime(t0 + day * 86400)[:3] + (0, 0, 0, 0, 0, -1))
    return b + hours * 3600
# routine noise
t = t0
while t < now:
    for c, *_ in cams:
        if r.random() < 0.9:
            nvr.append((t + r.uniform(0, 60), "INFO ", "rec %s: segment closed, 900 s, %d MB" % (c, r.randint(150, 260))))
    if r.random() < 0.5:
        sw2.append((t + r.uniform(0, 900), "%CDP-4-NATIVE_VLAN_MISMATCH: Native VLAN mismatch discovered on GigabitEthernet1/0/10 (1), with sw-1f GigabitEthernet1/0/24 (30)."))
        sw1.append((t + r.uniform(0, 900), "%CDP-4-NATIVE_VLAN_MISMATCH: Native VLAN mismatch discovered on GigabitEthernet1/0/24 (30), with sw-2f GigabitEthernet1/0/10 (1)."))
    if r.random() < 0.15:
        p = r.choice([2, 3, 11, 12])
        tt = t + r.uniform(0, 600)
        sw2.append((tt, "%%LINK-3-UPDOWN: Interface GigabitEthernet1/0/%d, changed state to down" % p))
        sw2.append((tt + 1, "%%LINEPROTO-5-UPDOWN: Line protocol on Interface GigabitEthernet1/0/%d, changed state to down" % p))
        sw2.append((tt + r.uniform(4, 200), "%%LINK-3-UPDOWN: Interface GigabitEthernet1/0/%d, changed state to up" % p))
    if r.random() < 0.05:
        sw2.append((t + r.uniform(0, 900), "%%DHCP_SNOOPING-5-DHCP_SNOOPING_UNTRUSTED_PORT: DHCP_SNOOPING drop message on untrusted port, message type: DHCPOFFER, MAC sa: 3c:52:82:%02x:%02x:%02x" % (r.randrange(256), r.randrange(256), r.randrange(256))))
    t += 900
sw2.append((t0 + 30000, "%SEC_LOGIN-5-LOGIN_SUCCESS: Login Success [user: netadmin] [Source: 10.50.0.20] [localport: 22]"))
sw2.append((t0 + 30400, "%SYS-5-CONFIG_I: Configured from console by netadmin on vty0 (10.50.0.20)"))
# the fault: IR on at dusk -> PoE budget exceeded on sw-2f -> ports 5-8 denied / flapping all night
def deny(ts, port, req):
    sw2.append((ts, "%%ILPOWER-4-BUDGET_EXCEEDED: PoE power budget exceeded: requested %.1f W, available 67.0 W" % req))
    sw2.append((ts + 0.2, "%%ILPOWER-5-ILPOWER_POWER_DENY: Interface Gi1/0/%d: inline power denied. Reason: insufficient power" % port))
    sw2.append((ts + 0.4, "%%ILPOWER-5-IEEE_DISCONNECT: Interface Gi1/0/%d: PD removed" % port))
    sw2.append((ts + 1.0, "%%LINK-3-UPDOWN: Interface GigabitEthernet1/0/%d, changed state to down" % port))
    nvr.append((ts + r.uniform(8, 12), "WARN ", "stream cam0%d: no frames for 10 s, marking OFFLINE" % port))
def grant(ts, port):
    sw2.append((ts, "%%ILPOWER-7-DETECT: Interface Gi1/0/%d: Power Device detected: IEEE PD" % port))
    sw2.append((ts + 0.5, "%%ILPOWER-5-POWER_GRANTED: Interface Gi1/0/%d: Power granted" % port))
    sw2.append((ts + 3, "%%LINK-3-UPDOWN: Interface GigabitEthernet1/0/%d, changed state to up" % port))
    nvr.append((ts + r.uniform(45, 70), "INFO ", "stream cam0%d: reconnected" % port))
for day in range(4):
    dusk = at(day, 18.9 + r.uniform(0, 0.15))
    mo = at(day, 6.8 + r.uniform(0, 0.25))
    if t0 < mo < now:
        for c in (1, 2, 3, 4):
            nvr.append((mo + r.uniform(0, 300), "INFO ", "cam0%d: day/night switch -> DAY (IR illuminator off)" % c))
    if not (t0 < dusk < now - 600):
        continue
    for c in (1, 2, 3, 4, 5, 6, 7, 8):
        nvr.append((dusk + r.uniform(-120, 90), "INFO ", "cam0%d: day/night switch -> NIGHT (IR illuminator on)" % c))
    first = dusk + r.uniform(100, 160)
    deny(first, 8, 74.9 + r.uniform(0, 2))
    deny(first + r.uniform(2, 6), 7, 69.1 + r.uniform(0, 2))
    deny(first + r.uniform(8, 20), 6, 68.2 + r.uniform(0, 2))
    deny(first + r.uniform(25, 40), 5, 67.4 + r.uniform(0, 1))
    dawn = at(day + 1, 6.8 + r.uniform(0, 0.25))
    ts, end = first + 300, min(dawn, now - 60)
    while ts < end:                      # ports retry, boot in the dark, IR on, denied again
        p = r.choice([5, 6, 7, 8])
        grant(ts, p)
        d = ts + r.uniform(90, 160)
        nvr.append((d - r.uniform(2, 6), "INFO ", "cam0%d: day/night switch -> NIGHT (IR illuminator on)" % p))
        deny(d, p, 67.5 + r.uniform(1, 9))
        ts += r.uniform(240, 600)
    if dawn < now:
        for p in (5, 6, 7, 8):
            g = dawn + r.uniform(60, 600)
            if g < now:
                grant(g, p)
nvr.append((t0 + 9000, "ERROR", "rec cam02: segment write slow (1840 ms), disk busy"))
def dump(path, rows, host, nvrfmt=False):
    rows.sort()
    with open(path, "w") as f:
        for n, (ts, *m) in enumerate(rows, 1000):
            if nvrfmt:
                f.write("%s %s nvr: %s\n" % (time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(ts)), m[0], m[1]))
            else:
                f.write("%s %s %d: %s\n" % (time.strftime("%b %e %H:%M:%S", time.localtime(ts)), host, n, m[0]))
dump("/var/log/nvr/nvr.log", nvr, "", True)
dump("/var/log/remote/switch-2f.log", sw2, "sw-2f")
dump("/var/log/remote/switch-1f.log", sw1, "sw-1f")
PY
chmod -R a+rX /etc/nvr /var/log/nvr /var/log/remote
