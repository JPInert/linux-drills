install -d -m 0755 /var/log/nvr
python3 - <<'PY'
import datetime, os, random
r = random.Random(os.urandom(16))
D1, D2 = datetime.date(2026, 9, 22), datetime.date(2026, 9, 23)

def stamp(day, sec):
    return "%s %02d:%02d:%02d" % (day.isoformat(), sec // 3600, sec // 60 % 60, sec % 60)

# ---- auth.log
legit = ["10.50.2.%d" % i for i in range(10, 30)]
bad = r.sample(["10.50.9.%d" % i for i in range(2, 250)], 4)
top, decoy = bad[0], bad[1]
fails = {top: r.randint(180, 260), decoy: r.randint(90, 140), bad[2]: r.randint(40, 80), bad[3]: r.randint(10, 30)}
ev = []
for ip, n in fails.items():
    for _ in range(n):
        ev.append((r.choice([D1, D2]), r.randrange(86400), "AUTH FAIL user=%s ip=%s reason=bad_password" % (r.choice(["admin", "root", "operator", "guard"]), ip)))
for _ in range(r.randint(420, 520)):          # the decoy also LOGS IN a lot: most lines overall
    ev.append((r.choice([D1, D2]), r.randrange(86400), "AUTH OK   user=operator ip=%s" % decoy))
for ip in legit:
    for _ in range(r.randint(8, 30)):
        ev.append((r.choice([D1, D2]), r.randrange(86400), "AUTH OK   user=%s ip=%s" % (r.choice(["guard", "operator"]), ip)))
    for _ in range(r.randint(0, 6)):
        ev.append((r.choice([D1, D2]), r.randrange(86400), "AUTH FAIL user=guard ip=%s reason=bad_password" % ip))
ev.sort(key=lambda e: (e[0], e[1]))
with open("/var/log/nvr/auth.log", "w") as f:
    for d, s, m in ev:
        f.write("%s %s\n" % (stamp(d, s), m))
true_fails = sum(1 for e in ev if "AUTH FAIL" in e[2] and "ip=%s " % top in e[2] + " ")

# ---- access.log: date time ip method path status bytes ua
clients = legit + ["10.50.1.31"]
busy = r.choice(clients)
paths = ["/api/cam/%d/snapshot", "/api/cam/%d/stream", "/api/events", "/login", "/static/app.js"]
rows = []
def add(day, sec, ip, method, path, status, size):
    rows.append((day, sec, "%s %s %s %s %d %d \"nvr-client/2.1\"" % (stamp(day, sec), ip, method, path, status, size)))
cam404 = {c: r.randint(20, 60) for c in range(1, 9)}
star = r.randint(1, 8); cam404[star] = 95 + r.randint(0, 20)
for c, n in cam404.items():
    for _ in range(n):
        add(r.choice([D1, D2]), r.randrange(86400), r.choice(clients), "GET", "/api/cam/%d/snapshot" % c, 404, r.randint(120, 300))
for _ in range(38000):
    ip = busy if r.random() < 0.3 else r.choice(clients)
    p = r.choice(paths)
    if "%d" in p:
        p = p % r.randint(1, 8)
    st = r.choices([200, 304, 302, 401, 500, 502, 503], [80, 8, 3, 3, 2, 1, 1])[0]
    add(r.choice([D1, D2]), r.randrange(86400), ip, r.choice(["GET", "GET", "GET", "POST"]), p, st, r.randint(200, 90000))
K = r.randint(37, 61)                                    # 5xx in the asked window
for _ in range(K):
    add(D2, 2 * 3600 + r.randrange(3600), r.choice(clients), "GET", r.choice(paths[:3]).replace("%d", str(r.randint(1, 8))), r.choice([500, 502, 503]), r.randint(100, 900))
for _ in range(9):                                       # 200s whose BYTES field looks like 5xx, inside the window
    add(D2, 2 * 3600 + r.randrange(3600), r.choice(clients), "GET", "/api/events", 200, r.randint(500, 599))
rows = [x for x in rows]
rows.sort(key=lambda x: (x[0], x[1]))
with open("/var/log/nvr/access.log", "w") as f:
    for _, _, line in rows:
        f.write(line + "\n")
# recompute truth from what was written (so the check can never disagree with the file)
n5 = 0
n404 = {}
for line in open("/var/log/nvr/access.log"):
    p = line.split()
    if p[0] == "2026-09-23" and p[1].startswith("02:") and p[5].startswith("5"):
        n5 += 1
    if p[5] == "404":
        c = p[4].split("/")[3]; n404[c] = n404.get(c, 0) + 1
cam = max(n404, key=n404.get)
tf = {}
for line in open("/var/log/nvr/auth.log"):
    if "AUTH FAIL" in line:
        ip = line.split("ip=")[1].split()[0]; tf[ip] = tf.get(ip, 0) + 1
tip = max(tf, key=tf.get)
assert sorted(tf.values())[-1] > sorted(tf.values())[-2] and sorted(n404.values())[-1] > sorted(n404.values())[-2]
with open("/var/lib/drill/.expected", "w") as f:
    f.write("EXP_IP=%s\nEXP_FAILS=%d\nEXP_5XX=%d\nEXP_CAM=%s\n" % (tip, tf[tip], n5, cam))
os.chmod("/var/lib/drill/.expected", 0o600)
PY
chmod 0644 /var/log/nvr/*.log
