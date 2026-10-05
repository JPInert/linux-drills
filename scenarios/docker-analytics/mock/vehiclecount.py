# drill mock: the vehicle-count container's process (python3 -m vehiclecount)
# Logs go to the container's json-file log (docker logs reads it). On the GPU it
# publishes /run/mock-gpu/<name>.json so the mock nvidia-smi lists this PID.
import json, os, random, signal, sys, time

LOG = os.environ.get("MOCKD_LOG", "/dev/null")
NAME = os.environ.get("MOCKD_NAME", "vehicle-count")
GPU_FILE = "/run/mock-gpu/%s.json" % NAME
VER = os.environ.get("FD_VERSION", "2.4.1")
CAMS = 6


def iso(t):
    return time.strftime("%Y-%m-%dT%H:%M:%S", time.gmtime(t)) + ".%09dZ" % int((t % 1) * 1e9)


def write(lines, t=None, stream="stdout", f=None):
    t = time.time() if t is None else t
    own = f is None
    f = f or open(LOG, "a")
    for ln in lines:
        f.write(json.dumps({"log": ln + "\n", "stream": stream, "time": iso(t)}) + "\n")
    if own:
        f.close()


def app(t, level, msg):
    return "%s %-5s vehiclecount: %s" % (time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(t)),
                                      level, msg)


def decide():
    dev = os.environ.get("FD_DEVICE", "auto").strip().lower()
    cvd = os.environ.get("CUDA_VISIBLE_DEVICES")
    nvd = os.environ.get("NVIDIA_VISIBLE_DEVICES", "all")
    gpu = os.environ.get("MOCKD_GPU") == "1" and nvd not in ("", "void", "none") \
        and not (cvd is not None and cvd.strip() in ("", "-1"))
    if dev == "cpu":
        return "cpu-forced"
    return "gpu" if gpu else "cpu"


def startup(t, mode):
    L, E = [], []
    L.append(app(t, "INFO", "vehiclecount %s starting (build 7c1e9a2), config /app/config.yaml"
                 % VER))
    L.append(app(t, "INFO", "model: %s" % os.environ.get("FD_MODEL", "/models/fall-pose-v7.engine")))
    if mode == "gpu":
        L.append(app(t, "INFO", "CUDA device 0: NVIDIA RTX A2000 12GB (compute 8.6, "
                     "driver 535.183.01, CUDA 12.2)"))
        L.append(app(t, "INFO", "TensorRT engine loaded on cuda:0 (2410 MiB), batch=6"))
    elif mode == "cpu-forced":
        L.append(app(t, "INFO", "FD_DEVICE=cpu: GPU disabled by configuration"))
        L.append(app(t, "INFO", "TensorRT engine needs CUDA: using ONNX fallback "
                     "/models/fall-pose-v7.onnx on CPU (4 threads)"))
    else:
        E.append("/usr/local/lib/python3.10/dist-packages/torch/cuda/__init__.py:128: "
                 "UserWarning: CUDA initialization: Found no NVIDIA driver on your system. "
                 "Please check that you have an NVIDIA GPU and installed a driver from "
                 "http://www.nvidia.com/Download/index.aspx (Triggered internally at "
                 "../c10/cuda/CUDAFunctions.cpp:108.)")
        E.append("  return torch._C._cuda_getDeviceCount() > 0")
        L2 = [app(t, "WARN", "CUDA not available, falling back to CPU "
                  "(expect ~10x slower inference)"),
              app(t, "INFO", "TensorRT engine needs CUDA: using ONNX fallback "
                  "/models/fall-pose-v7.onnx on CPU (4 threads)")]
    src = os.environ.get("FD_RTSP_SOURCE", "rtsp://127.0.0.1:8554")
    tail = [app(t, "INFO", "rtsp: %d/%d streams connected via %s (cam01..cam%02d)"
                % (CAMS, CAMS, src, CAMS)),
            app(t, "INFO", "alerts -> %s" % os.environ.get(
                "FD_ALERT_URL", "https://alerts.facility.lan/api/v1/events"))]
    if mode == "cpu":
        return L, E, L2 + tail
    return L, E, tail


def stats(t, mode):
    if mode == "gpu":
        lat = random.randint(340, 520)
        return [app(t, "INFO", "stats cams=%d fps=15.0/cam infer_ms=%d queue=0 "
                    "device=cuda:0 alert_latency_ms=%d" % (CAMS, random.randint(28, 36), lat))]
    lat = random.randint(21000, 29000)
    return [app(t, "INFO", "stats cams=%d fps=%.1f/cam infer_ms=%d queue=%d device=cpu "
                "alert_latency_ms=%d" % (CAMS, random.uniform(1.6, 2.1),
                                         random.randint(1900, 2400),
                                         random.randint(280, 360), lat)),
            app(t, "WARN", "alert latency %.1fs over SLO 2.0s (frames are queuing)"
                % (lat / 1000.0))]


def publish():
    try:
        os.makedirs("/run/mock-gpu", exist_ok=True)
        tmp = GPU_FILE + ".tmp"
        with open(tmp, "w") as f:
            json.dump({"pid": os.getpid(), "name": "python3 -m vehiclecount",
                       "mem_mib": 2410, "util": 47}, f)
        os.chmod(tmp, 0o644)
        os.replace(tmp, GPU_FILE)
    except OSError:
        pass


def bye(*_):
    try:
        with open(GPU_FILE) as f:
            if json.load(f).get("pid") == os.getpid():
                os.remove(GPU_FILE)
    except (OSError, ValueError):
        pass
    write([app(time.time(), "INFO", "SIGTERM: draining %d streams, bye" % CAMS)])
    sys.exit(0)


def main():
    signal.signal(signal.SIGTERM, bye)
    signal.signal(signal.SIGINT, bye)
    mode = decide()
    now = time.time()
    bd = os.environ.get("MOCKD_BACKDATE")
    t0 = float(bd) if bd else now
    out1, err, out2 = startup(t0, mode)
    with open(LOG, "a") as f:
        write(out1, t0, f=f)
        write(err, t0, "stderr", f=f)
        write(out2, t0 + 1, f=f)
        if bd:                                      # history since the (backdated) start
            t = t0 + 30
            while t < now - 5:
                write(stats(t, mode), t, f=f)
                t += 60
    if mode == "gpu":
        publish()
    last_stats, last_pub = now - 25, now
    busy = mode != "gpu"
    while True:
        n = time.time()
        if busy:                                    # CPU inference: burn some real CPU
            end = n + 0.08
            while time.time() < end:
                pass
            time.sleep(0.32)
        else:
            time.sleep(0.5)
        n = time.time()
        if n - last_stats >= 30:
            last_stats = n
            write(stats(n, mode), n)
        if mode == "gpu" and n - last_pub >= 2:
            last_pub = n
            publish()


main()
