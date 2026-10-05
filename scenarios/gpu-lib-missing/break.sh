/usr/local/lib/drill/analytics-install --no-start
# the daemon runs as `analytics` and must be able to publish its GPU state for nvidia-smi to list it
install -d -o analytics -g analytics /run/mock-gpu
# A CUDA 12.2 runtime that ldconfig genuinely understands: tiny ELF shared objects with a SONAME
# (contents are empty stubs padded to a realistic size)
python3 - <<'PY'
import os, struct
D = "/usr/local/cuda/lib64"
def mkso(name, soname, size):
    strtab = b"\0" + soname.encode() + b"\0"
    ph_off, ph_sz, nph = 64, 56, 2
    str_off = ph_off + ph_sz * nph
    dyn_off = (str_off + len(strtab) + 7) & ~7
    dyn = b"".join(struct.pack("<qQ", t, v) for t, v in ((14, 1), (5, str_off), (10, len(strtab)), (0, 0)))
    total = dyn_off + len(dyn)
    eh = b"\x7fELF" + bytes([2, 1, 1, 0]) + b"\0" * 8
    eh += struct.pack("<HHIQQQIHHHHHH", 3, 62, 1, 0, ph_off, 0, 0, 64, ph_sz, nph, 64, 0, 0)
    ph = struct.pack("<IIQQQQQQ", 1, 4, 0, 0, 0, total, total, 0x1000)
    ph += struct.pack("<IIQQQQQQ", 2, 6, dyn_off, dyn_off, dyn_off, len(dyn), len(dyn), 8)
    data = eh + ph + strtab
    data += b"\0" * (dyn_off - len(data)) + dyn
    with open(os.path.join(D, name), "wb") as f:
        f.write(data)
        f.truncate(max(size, len(data)))          # sparse padding
    os.chmod(os.path.join(D, name), 0o644)
mkso("libcudart.so.12.2.140", "libcudart.so.12", 729088)
mkso("libcublas.so.12.2.5.6", "libcublas.so.12", 96 * 1024 * 1024)
mkso("libcublasLt.so.12.2.5.6", "libcublasLt.so.12", 210 * 1024 * 1024)
mkso("libnvrtc.so.12.2.140", "libnvrtc.so.12", 48 * 1024 * 1024)
PY
cd /usr/local/cuda/lib64
ln -sfn libcudart.so.12.2.140  libcudart.so.12
ln -sfn libcublas.so.12.2.5.6  libcublas.so.12
ln -sfn libcublasLt.so.12.2.5.6 libcublasLt.so.12
ln -sfn libnvrtc.so.12.2.140   libnvrtc.so.12
echo /usr/local/cuda/lib64 > /etc/ld.so.conf.d/cuda.conf
ldconfig                                    # loader cache built while everything was healthy
# the overnight "update": the link was flipped to the new minor version, its payload never arrived
ln -sfn libcudart.so.12.4.99 libcudart.so.12
cd /
systemctl start analytics
sleep 2
