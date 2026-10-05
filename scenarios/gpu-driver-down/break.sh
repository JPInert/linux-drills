/usr/local/lib/drill/analytics-install --no-start
# the daemon runs as `analytics` and must be able to publish its GPU state for nvidia-smi to list it
install -d -o analytics -g analytics /run/mock-gpu

# --- mock nvidia-persistenced: the (mock) driver only answers while this daemon is up; stopping it takes it away
cat > /usr/bin/nvidia-persistenced <<'PY'
#!/usr/bin/python3
# drill mock of nvidia-persistenced
import os, signal, socket, sys
FAULT = "/run/mock-gpu/driver_fault"

def log(m):
    print(m, flush=True)

def notify(msg):
    a = os.environ.get("NOTIFY_SOCKET")
    if a:
        s = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
        s.connect("\0" + a[1:] if a[0] == "@" else a)
        s.send(msg.encode())
        s.close()

def stop(*_):
    open(FAULT, "w").close()
    log("Shutdown (%d)" % os.getpid())
    sys.exit(0)

if not os.environ.get("NOTIFY_SOCKET"):            # started by hand: daemonise like the real one
    if os.fork():
        sys.exit(0)
    os.setsid()
    fd = os.open(os.devnull, os.O_RDWR)
    for n in (0, 1, 2):
        os.dup2(fd, n)
signal.signal(signal.SIGTERM, stop)
signal.signal(signal.SIGINT, stop)
try:
    os.remove(FAULT)
except FileNotFoundError:
    pass
log("Verbose syslog connection opened")
log("Started (%d)" % os.getpid())
log("device 0000:01:00.0 - registered")
log("device 0000:01:00.0 - persistence mode enabled.")
log("Local RPC services initialized")
notify("READY=1")
while True:
    signal.pause()
PY
chmod 0755 /usr/bin/nvidia-persistenced
# vendor unit, shipped disabled (the maintenance tool re-applied the vendor defaults)
cat > /usr/lib/systemd/system/nvidia-persistenced.service <<'UNIT'
[Unit]
Description=NVIDIA Persistence Daemon
After=network.target

[Service]
Type=notify
ExecStart=/usr/bin/nvidia-persistenced --verbose
TimeoutStartSec=20

[Install]
WantedBy=multi-user.target
UNIT

# --- kernel-side tools the container does not have (kmod is not installed): the NVIDIA modules ARE loaded
cat > /usr/local/bin/lsmod <<'SH'
#!/bin/sh
cat <<'MODS'
Module                  Size  Used by
nvidia_uvm           1568768  0
nvidia_drm             81920  0
nvidia_modeset       1294336  1 nvidia_drm
nvidia              56336384  2 nvidia_uvm,nvidia_modeset
drm_kms_helper        212992  1 nvidia_drm
drm                   614400  4 drm_kms_helper,nvidia,nvidia_drm
video                  65536  1 nvidia_modeset
nvme                   57344  2
nvme_core             167936  3 nvme
e1000e                290816  0
xhci_pci               24576  0
xhci_hcd              294912  1 xhci_pci
ext4                  983040  1
MODS
SH
cat > /usr/local/bin/modprobe <<'SH'
#!/bin/sh
# containers cannot load kernel modules: the NVIDIA ones are already loaded on this box
rm=0; mod=
for a in "$@"; do case $a in -r|--remove) rm=1 ;; -*) ;; *) mod=$a ;; esac; done
case $mod in
  nvidia|nvidia_uvm|nvidia_modeset|nvidia_drm)
    if [ $rm = 1 ]; then echo "modprobe: FATAL: Module $mod is in use." >&2; exit 1; fi
    exit 0 ;;
esac
echo "modprobe: FATAL: Module ${mod:-?} not found in directory /lib/modules/$(uname -r)" >&2; exit 1
SH
cat > /usr/local/bin/modinfo <<'SH'
#!/bin/sh
case "$1" in nvidia|nvidia_uvm|nvidia_modeset|nvidia_drm) ;; *) echo "modinfo: ERROR: Module ${1:-?} not found." >&2; exit 1 ;; esac
cat <<INFO
filename:       /lib/modules/$(uname -r)/updates/dkms/$1.ko
version:        535.183.01
supported:      external
license:        NVIDIA
srcversion:     3F0C6B1E8A529D471C0E5B7
alias:          pci:v000010DEd*sv*sd*bc03sc02i00*
alias:          pci:v000010DEd*sv*sd*bc03sc00i00*
depends:        $( [ "$1" = nvidia ] && echo "" || echo nvidia )
retpoline:      Y
name:           $1
vermagic:       $(uname -r) SMP preempt mod_unload modversions
INFO
SH
chmod 0755 /usr/local/bin/lsmod /usr/local/bin/modprobe /usr/local/bin/modinfo

systemctl daemon-reload
# the reboot happened with the driver stack down: analytics started, could not get the GPU and fell back to CPU
touch /run/mock-gpu/driver_fault
systemctl start analytics
sleep 2
