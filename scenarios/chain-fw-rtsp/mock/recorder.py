#!/usr/bin/python3
"""nvr-recorder: hold an RTSP session to each camera for the vehicle-count pipeline."""
import base64, json, os, socket, time

CONF = "/etc/nvr-recorder/cameras.conf"
STATUS = "/run/nvr-recorder/status.json"


def log(m):
    print(m, flush=True)


def load():
    cams, cfg = [], {}
    for line in open(CONF):
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, _, v = line.partition("=")
        k, v = k.strip(), v.strip()
        if k == "CAMERA":                      # CAMERA=name url user pass
            name, url, user, pw = v.split()
            cams.append((name, url, user, pw))
        else:
            cfg[k] = v
    return cfg, cams


def describe(url, user, pw, cseq, tmo):
    host, _, port = url.split("://", 1)[1].split("/", 1)[0].partition(":")
    req = "DESCRIBE %s RTSP/1.0\r\nCSeq: %d\r\nAccept: application/sdp\r\nUser-Agent: nvr-recorder/5.2\r\n" % (url, cseq)
    req += "Authorization: Basic %s\r\n\r\n" % base64.b64encode(("%s:%s" % (user, pw)).encode()).decode()
    with socket.create_connection((host, int(port or 554)), timeout=tmo) as s:
        s.sendall(req.encode())
        data = b""
        while b"\r\n\r\n" not in data:
            chunk = s.recv(4096)
            if not chunk:
                break
            data += chunk
    return data.split(b"\r\n", 1)[0].decode("latin-1") or "(empty reply)"


def main():
    cfg, cams = load()
    every, tmo = float(cfg.get("RETRY_SECONDS", "3")), float(cfg.get("CONNECT_TIMEOUT", "3"))
    log("nvr-recorder 5.2 starting: %d cameras" % len(cams))
    cseq, state = 0, {}
    while True:
        for name, url, user, pw in cams:
            cseq += 1
            hp = url.split("://", 1)[1].split("/", 1)[0]
            hp = hp if ":" in hp else hp + ":554"
            try:
                st = describe(url, user, pw, cseq, tmo)
                up = st.startswith("RTSP/1.0 200")
                log("%s: DESCRIBE %s -> %s%s" % (name, url, st, ", stream up" if up else ""))
            except socket.timeout:
                up = False
                log("%s: RTSP connect to %s timed out after %gs, reconnecting" % (name, hp, tmo))
            except OSError as e:
                up = False
                log("%s: RTSP connect to %s failed: %s, reconnecting" % (name, hp, e.strerror or e))
            state[name] = {"url": url, "tile": "live" if up else "reconnecting"}
        tmp = STATUS + ".tmp"
        with open(tmp, "w") as f:
            json.dump({"at": time.strftime("%Y-%m-%dT%H:%M:%S"), "cameras": state}, f, indent=1)
            f.write("\n")
        os.replace(tmp, STATUS)
        time.sleep(every)


main()
