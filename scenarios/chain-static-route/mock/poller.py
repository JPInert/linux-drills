#!/usr/bin/python3
"""sensor-poller: poll the sensor hubs for the care dashboard (bed-exit / door sensors)."""
import json, os, socket, time, urllib.request

CONF = "/etc/sensor-poller/poller.conf"
OUT = "/run/sensor-poller/dashboard.json"


def log(m):
    print(m, flush=True)


def load():
    cfg, hubs = {}, []
    for line in open(CONF):
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, _, v = line.partition("=")
        k, v = k.strip(), v.strip()
        if k == "HUB":
            name, _, ip = v.rpartition(" ")
            hubs.append((name.strip() or ip, ip))
        else:
            cfg[k] = v
    return cfg, hubs


def main():
    cfg, hubs = load()
    every = float(cfg.get("POLL_SECONDS", "3"))
    tmo = float(cfg.get("TIMEOUT_SECONDS", "2"))
    log("sensor-poller 2.4 starting: %d hubs, poll every %gs" % (len(hubs), every))
    while True:
        board = []
        for name, ip in hubs:
            url = "http://%s/status" % ip
            try:
                with urllib.request.urlopen(url, timeout=tmo) as r:
                    d = json.load(r)
                log("%s %s: OK %d/%d sensors online" % (name, ip, d["online"], d["sensors"]))
                board.append({"hub": name, "ip": ip, "state": "ok", "online": d["online"]})
            except Exception as e:
                why = getattr(e, "reason", e)
                if isinstance(why, (socket.timeout, TimeoutError)) or "timed out" in str(why):
                    why = "timed out after %gs" % tmo
                log("%s %s: poll failed: %s" % (name, ip, why))
                board.append({"hub": name, "ip": ip, "state": "no data"})
        tmp = OUT + ".tmp"
        with open(tmp, "w") as f:
            json.dump({"at": time.strftime("%Y-%m-%dT%H:%M:%S"), "hubs": board}, f, indent=1)
            f.write("\n")
        os.replace(tmp, OUT)
        time.sleep(every)


main()
