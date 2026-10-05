python3 - <<'PY'
import os, random
r = random.Random(os.urandom(16))
os.makedirs("/etc/nvr/conf.d", exist_ok=True)
open("/etc/nvr/README", "w").write("""NVR configuration loading
  1. /etc/nvr/nvr.conf is read first.
  2. Then every file in /etc/nvr/conf.d/ whose name ends in .conf, in name order (10-, 20-, 50-, ...).
  3. Later files override earlier ones: the LAST assignment of a key wins.
  4. Lines starting with # are comments. Files that do not end in .conf (backups, .disabled, .dpkg-old) are ignored.
  5. Settings are KEY=VALUE, one per line.
""")
filler = ["RTSP_TIMEOUT=%d", "SNAPSHOT_QUALITY=%d", "RETENTION_DAYS=%d", "MAX_STREAMS=%d", "LOG_ROTATE_MB=%d", "API_PORT=%d", "BUFFER_KB=%d"]
def body(lines_before, marker_lines, lines_after):
    out = []
    for _ in range(lines_before):
        out.append(r.choice(filler) % r.randint(2, 900))
    out += marker_lines
    for _ in range(lines_after):
        out.append(r.choice(filler) % r.randint(2, 900))
    return out
def w(path, lines):
    open(path, "w").write("\n".join(lines) + "\n")
v = [r.choice([15, 20, 45, 60, 90, 120, 180, 240, 300]) for _ in range(5)]
while len(set(v)) < 5 or 30 in v:
    v = [r.choice([15, 20, 45, 60, 90, 120, 180, 240, 300, 420]) for _ in range(5)]
winner = r.choice(["50-site.conf", "60-tuning.conf"])
before = r.randint(2, 9)
w("/etc/nvr/nvr.conf", ["# NVR main configuration"] + body(r.randint(2, 6), ["# WATCHDOG_INTERVAL=30   (documented default, left commented)"], 3))
w("/etc/nvr/conf.d/10-cameras.conf", ["# cameras"] + body(3, ["WATCHDOG_INTERVAL_MAX=%d" % v[0]], 2))
w("/etc/nvr/conf.d/20-analytics.conf", ["# analytics"] + body(r.randint(1, 5), ["WATCHDOG_INTERVAL=%d" % v[1]], 4))
final_lines = ["# site overrides"] + body(before, ["WATCHDOG_INTERVAL=%d" % v[2]], r.randint(2, 6))
if winner == "50-site.conf":
    w("/etc/nvr/conf.d/50-site.conf", final_lines)
    w("/etc/nvr/conf.d/60-tuning.conf", ["# tuning"] + body(4, [], 3))
    expect_file, expect_lines = "/etc/nvr/conf.d/50-site.conf", final_lines
else:
    w("/etc/nvr/conf.d/50-site.conf", ["# site"] + body(3, ["WATCHDOG_INTERVAL=%d" % v[4]], 2))
    w("/etc/nvr/conf.d/60-tuning.conf", final_lines)
    expect_file, expect_lines = "/etc/nvr/conf.d/60-tuning.conf", final_lines
w("/etc/nvr/conf.d/50-site.conf.dpkg-old", ["# saved by dpkg"] + body(2, ["WATCHDOG_INTERVAL=%d" % v[3]], 2))
w("/etc/nvr/conf.d/90-legacy.conf.disabled", ["# disabled"] + body(3, ["WATCHDOG_INTERVAL=%d" % (v[3] + 7)], 2))
w("/etc/default/nvr", ["# service environment (not read by the config loader)", "NVR_HOME=/opt/nvr", "WATCHDOG_INTERVAL_OVERRIDE=%d" % (v[0] + 1)])
# ground truth: recompute from disk with the README rules
files = ["/etc/nvr/nvr.conf"] + sorted("/etc/nvr/conf.d/" + f for f in os.listdir("/etc/nvr/conf.d") if f.endswith(".conf"))
hit = None
for f in files:
    for n, line in enumerate(open(f), 1):
        if line.startswith("WATCHDOG_INTERVAL="):
            hit = (f, n, line.strip().split("=")[1])
with open("/var/lib/drill/.expected", "w") as f:
    f.write("EXP_FILE=%s\nEXP_LINE=%d\nEXP_VALUE=%s\n" % hit)
os.chmod("/var/lib/drill/.expected", 0o600)
PY
chmod -R a+rX /etc/nvr /etc/default/nvr
