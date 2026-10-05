/usr/local/lib/drill/analytics-install
install -d /opt/motion-buffer /opt/videoproc

cat > /etc/motion-buffer.conf <<'CONF'
# motion-buffer: pre-roll ring buffer for motion clips (kept in RAM)
# PREROLL_MB was 32. Raised while chasing missing pre-roll on cam-03 (ticket 4471), never put back.
PREROLL_MB=270
CONF

# --- the hog: allocates AND touches its buffer, so it is real resident memory (RSS)
cat > /opt/motion-buffer/motion-buffer <<'PY'
#!/usr/bin/python3
import time
mb = 32
for line in open("/etc/motion-buffer.conf"):
    line = line.strip()
    if line.startswith("PREROLL_MB="):
        mb = int(line.split("=", 1)[1])
slots = [bytearray(b"\xa5") * (10 << 20) for _ in range(mb // 10)]   # bytearray(b"x") * N writes every byte
print("motion-buffer: pre-roll buffer allocated: %d MB (%d slots x 10 MB), eviction disabled" % (len(slots) * 10, len(slots)), flush=True)
n = 0
while True:
    time.sleep(30)
    n += 1
    print("motion-buffer: %d MB resident, %d clips waiting, 0 evicted" % (len(slots) * 10, n * 3), flush=True)
PY
# --- a legitimate mid-sized resident: the transcoder's frame pool
cat > /opt/videoproc/videoproc <<'PY'
#!/usr/bin/python3
import time
pool = bytearray(b"\x5a") * (40 << 20)
print("videoproc: transcoder pool up (4 slots, 40 MB frame pool)", flush=True)
while True:
    t = time.time()
    while time.time() - t < 0.02:
        pass
    time.sleep(1)
PY
chmod 0755 /opt/motion-buffer/motion-buffer /opt/videoproc/videoproc

mkunit() {  # mkunit <name> <description>
cat > /usr/lib/systemd/system/$1.service <<UNIT
[Unit]
Description=$2
After=network.target

[Service]
ExecStart=/opt/$1/$1
Restart=no
CPUAccounting=yes
MemoryAccounting=yes

[Install]
WantedBy=multi-user.target
UNIT
}
mkunit motion-buffer "Motion clip pre-roll buffer"
mkunit videoproc     "Video transcoder pool"
systemctl daemon-reload
systemctl enable --now videoproc motion-buffer >/dev/null 2>&1
sleep 4
