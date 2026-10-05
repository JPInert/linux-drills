#!/usr/bin/env python3
"""Fake edge video-analytics daemon used by the drills (no real model, no real GPU).

Behaviour is driven by /etc/analytics/analytics.conf and the environment so that
scenarios can break it in realistic ways:
  LOG_LEVEL=DEBUG      -> ~2000 log lines/second (runaway log)
  DEVICE=cuda|cpu      -> which device it *wants*
  CUDA_VISIBLE_DEVICES -> '' or '-1' hides the GPU
  /usr/local/cuda/lib64/libcudart.so.12 must resolve for cuda
  other live /run/mock-gpu/*.json holders -> out of VRAM if < MODEL_MIB left
It writes /run/mock-gpu/analytics.json while it "holds" the GPU; the mock nvidia-smi reads that.
If /run/mock-gpu/card.state exists (thermal/power drills) it follows the card's real SM clock
(nvidia-smi --query-gpu=clocks.sm): a throttled card means fewer fps and late alerts.
"""
import glob, json, os, random, signal, sys, time

CONF = os.environ.get("ANALYTICS_CONF", "/etc/analytics/analytics.conf")
GPU_STATE = "/run/mock-gpu/analytics.json"
CUDART = "/usr/local/cuda/lib64/libcudart.so.12"
VRAM_MIB, MODEL_MIB = 12288, 1874


def vram_used_by_others():
    """MiB held by OTHER live processes that publish to /run/mock-gpu (the mock nvidia-smi reads the same files)."""
    used = 0
    for p in glob.glob("/run/mock-gpu/*.json"):
        if p == GPU_STATE:
            continue
        try:
            d = json.load(open(p))
            try:
                os.kill(d["pid"], 0)
            except PermissionError:
                pass                                    # alive, another user's
            used += int(d.get("mem_mib", 0))
        except Exception:
            continue
    return used


def load_conf(path):
    cfg = {}
    with open(path) as f:                       # PermissionError propagates on purpose
        for line in f:
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                cfg[k.strip()] = v.strip().strip('"')
    return cfg


def init_gpu(device):
    """-> (ok, reason).  Mirrors what a CUDA runtime would complain about."""
    if device != "cuda":
        return False, "DEVICE=%s in %s" % (device, CONF)
    cvd = os.environ.get("CUDA_VISIBLE_DEVICES")
    if cvd is not None and cvd.strip() in ("", "-1"):
        return False, "CUDA_ERROR_NO_DEVICE: no CUDA-capable device is detected (CUDA_VISIBLE_DEVICES=%r)" % cvd
    if not os.path.exists(CUDART):
        return False, "error while loading shared libraries: libcudart.so.12: cannot open shared object file: No such file or directory"
    if os.path.exists("/run/mock-gpu/driver_fault"):
        return False, "CUDA_ERROR_SYSTEM_DRIVER_MISMATCH: system has unsupported display driver / cuda driver combination"
    free = VRAM_MIB - vram_used_by_others()
    if free < MODEL_MIB:
        return False, "CUDA_ERROR_OUT_OF_MEMORY: out of memory: tried to allocate %d MiB (GPU 0; %d MiB total, %d MiB free)" % (MODEL_MIB, VRAM_MIB, max(free, 0))
    return True, ""


class Log:
    def __init__(self, path, level):
        self.path, self.level, self.f, self.last_err = path, level, None, 0
        self.open()

    def open(self):
        try:
            self.f = open(self.path, "a", buffering=1)
        except OSError as e:
            self.f = None
            self.err("cannot open %s: %s" % (self.path, e))

    def err(self, msg):
        now = time.time()
        if now - self.last_err > 10:                    # rate-limited to the journal
            print("ERROR detect: %s" % msg, file=sys.stderr, flush=True)
            self.last_err = now

    def write(self, text):
        if self.f is None:
            self.open()
            if self.f is None:
                return
        try:
            self.f.write(text)
        except OSError as e:
            self.err("cannot write %s: %s" % (self.path, e))


def clocked_fps():
    """fps follows the SM clock the card really runs at (throttled = slower)"""
    import subprocess
    try:
        r = subprocess.run(["nvidia-smi", "--query-gpu=clocks.sm", "--format=csv,noheader,nounits"],
                           capture_output=True, text=True, timeout=3)
        clk = int(r.stdout.strip().split()[0])
    except Exception:
        return 24.0, ""
    if clk < 500:                               # idle reading: our load isn't on the card yet
        return 24.0, ""
    fps = round(24.0 * min(1.0, clk / 1770.0), 1)
    return fps, " sm_clock=%dMHz" % clk


def main():
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    try:
        cfg = load_conf(CONF)
    except OSError as e:
        print("FATAL analytics: cannot read config %s: %s" % (CONF, e), file=sys.stderr, flush=True)
        sys.exit(1)
    level = cfg.get("LOG_LEVEL", "INFO").upper()
    log = Log(cfg.get("LOG_FILE", "/var/log/analytics/detect.log"), level)
    device = cfg.get("DEVICE", "cuda")
    cams = int(cfg.get("CAMERAS", "4"))
    ok, reason = init_gpu(device)
    ts = lambda: time.strftime("%Y-%m-%d %H:%M:%S")
    if ok:
        msg = "CUDA device 0 initialised: NVIDIA RTX A2000 12GB, using GPU inference (TensorRT)"
        print("INFO detect: " + msg, flush=True); log.write("%s INFO  detect: %s\n" % (ts(), msg))
    else:
        for m in ("CUDA init failed: " + reason, "falling back to CPU inference (expect ~1/12 throughput)"):
            print("WARN detect: " + m, flush=True); log.write("%s WARN  detect: %s\n" % (ts(), m))
    fps = 24.0 if ok else 2.0
    frame, last_hb, last_gpu = 0, 0.0, 0.0
    while True:
        now = time.time()
        if level == "DEBUG":
            lines = []
            for _ in range(40):
                frame += 1
                lines.append("%s DEBUG detect: frame=%d cam=cam-%02d bbox=[%d,%d,%d,%d] class=person conf=%.3f latency_ms=%.1f\n" % (
                    ts(), frame, frame % cams + 1, random.randrange(640), random.randrange(480),
                    random.randrange(640), random.randrange(480), random.random(), random.uniform(3, 60)))
            log.write("".join(lines))
            time.sleep(0.02)
        else:
            frame += int(fps)
            time.sleep(1)
        if now - last_hb >= 5:
            last_hb = now
            if ok and os.path.exists("/run/mock-gpu/card.state"):
                fps, extra = clocked_fps()
            else:
                extra = ""
            log.write("%s INFO  detect: cams=%d fps=%.1f device=%s frames=%d%s\n" % (ts(), cams, fps, "cuda:0" if ok else "cpu", frame, extra))
            if extra and fps < 20:
                log.write("%s WARN  detect: inference behind real time (%.1f fps < 24): alert latency %.1fs over SLO 2.0s\n" % (ts(), fps, 24.0 / fps * 1.9))
        if ok and now - last_gpu >= 2:
            last_gpu = now
            try:
                os.makedirs("/run/mock-gpu", exist_ok=True)
                with open(GPU_STATE, "w") as f:
                    json.dump({"pid": os.getpid(), "name": "/usr/bin/python3 /opt/analytics/analytics.py", "mem_mib": 1874, "util": 61}, f)
            except OSError:
                pass


if __name__ == "__main__":
    main()
