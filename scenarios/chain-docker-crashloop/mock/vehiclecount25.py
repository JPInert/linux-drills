# drill mock: vehicle-count 2.5.x (python3 -m vehiclecount). Loads the model named by
# FD_MODEL (a path INSIDE the container, resolved through its bind mounts); if the
# file is missing it logs the traceback and exits 1, so the restart policy turns
# it into a crash loop. On success it runs like the real detector (GPU if given).
import json, os, random, signal, sys, time
from mdcommon import write, write_many, host_path

NAME = os.environ.get("MOCKD_NAME", "vehicle-count")
GPU_FILE = "/run/mock-gpu/%s.json" % NAME
STATE = "/run/.drill-fd-state"
VER = os.environ.get("FD_VERSION", "2.5.0")
CAMS = 6


def app(level, msg, t=None):
    t = time.time() if t is None else t
    return "%s %-5s vehiclecount: %s" % (time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(t)),
                                      level, msg)


def out(lines, stream="stdout", t=None):
    for ln in lines:
        write(ln, t, stream)


def publish():
    try:
        os.makedirs("/run/mock-gpu", exist_ok=True)
        with open(GPU_FILE + ".tmp", "w") as f:
            json.dump({"pid": os.getpid(), "name": "python3 -m vehiclecount",
                       "mem_mib": 2630, "util": 44}, f)
        os.chmod(GPU_FILE + ".tmp", 0o644)
        os.replace(GPU_FILE + ".tmp", GPU_FILE)
    except OSError:
        pass


def bye(*_):
    try:
        with open(GPU_FILE) as f:
            if json.load(f).get("pid") == os.getpid():
                os.remove(GPU_FILE)
    except (OSError, ValueError):
        pass
    out([app("INFO", "SIGTERM: draining %d streams, bye" % CAMS)])
    sys.exit(0)


def crash_lines(model):
    return ["Traceback (most recent call last):",
            '  File "/app/vehiclecount/__main__.py", line 41, in <module>',
            "    main()",
            '  File "/app/vehiclecount/engine.py", line 118, in load',
            "    with open(path, \"rb\") as f:",
            "FileNotFoundError: [Errno 2] No such file or directory: '%s'" % model]


def main():
    signal.signal(signal.SIGTERM, bye)
    model = os.environ.get("FD_MODEL", "/models/fall-pose.engine")
    bd = os.environ.get("MOCKD_BACKDATE")
    head = lambda t: [app("INFO", "vehiclecount %s starting (build 91d04be), config "
                          "/app/config.yaml" % VER, t), app("INFO", "model: %s" % model, t)]
    t0 = float(bd) if bd else None
    out(head(t0), t=t0)
    hp = host_path(model)
    ok = bool(hp) and os.path.isfile(hp)
    if not ok and t0:               # history: crash, back off, crash ... since t0
        recs, t, d, n = [], t0, 0.1, 0
        while True:
            recs += [(ln, t, "stderr") for ln in crash_lines(model)]
            recs.append((app("FATAL", "cannot load model %s: No such file or directory, "
                             "exiting (code 1)" % model, t), t, "stdout"))
            d = min(d * 2, 60.0)
            t += d + 1
            n += 1
            if t > time.time() - 70 or n > 2000:
                break
            recs += [(x, t, "stdout") for x in head(t)]
        write_many(recs)
        out(head(None))
    if not ok:
        out(["Traceback (most recent call last):",
             '  File "/app/vehiclecount/__main__.py", line 41, in <module>',
             "    main()",
             '  File "/app/vehiclecount/engine.py", line 118, in load',
             "    with open(path, \"rb\") as f:",
             "FileNotFoundError: [Errno 2] No such file or directory: '%s'" % model],
            "stderr")
        out([app("FATAL", "cannot load model %s: No such file or directory, exiting (code 1)"
                 % model)])
        try:
            with open(STATE, "w") as f:
                f.write("crash %d %s\n" % (int(time.time()), model))
        except OSError:
            pass
        time.sleep(0.3)
        sys.exit(1)
    try:
        head = open(hp, "rb").read(200).decode("utf-8", "replace").strip()
    except OSError:
        head = ""
    mver = head.split("\n")[0] if head.startswith("fall-pose") else "fall-pose (unknown)"
    gpu = os.environ.get("MOCKD_GPU") == "1" and \
        os.environ.get("FD_DEVICE", "cuda").lower() != "cpu"
    if gpu:
        out([app("INFO", "CUDA device 0: NVIDIA RTX A2000 12GB (compute 8.6, driver "
                 "535.183.01, CUDA 12.2)"),
             app("INFO", "TensorRT engine loaded on cuda:0 (2630 MiB), batch=6: %s" % mver)])
        publish()
    else:
        out([app("WARN", "CUDA not available, running %s on CPU (expect ~10x slower)"
                 % mver)])
    out([app("INFO", "rtsp: %d/%d streams connected via %s (cam01..cam%02d)" % (
        CAMS, CAMS, os.environ.get("FD_RTSP_SOURCE", "rtsp://127.0.0.1:8554"), CAMS)),
         app("INFO", "alerts -> %s" % os.environ.get(
             "FD_ALERT_URL", "https://alerts.facility.lan/api/v1/events"))])
    try:
        with open(STATE, "w") as f:
            f.write("run %d %s %d %s\n" % (int(time.time()), model, os.getpid(), mver))
    except OSError:
        pass
    last = 0
    while True:
        time.sleep(1)
        n = time.time()
        if gpu and int(n) % 2 == 0:
            publish()
        if n - last >= 30:
            last = n
            out([app("INFO", "stats cams=%d fps=15.0/cam infer_ms=%d queue=0 device=%s "
                     "alert_latency_ms=%d" % (CAMS, random.randint(24, 31),
                                              "cuda:0" if gpu else "cpu",
                                              random.randint(300, 480)))])


main()
