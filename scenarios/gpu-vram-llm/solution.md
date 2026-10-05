# gpu-vram-llm: fall alerts late, a leftover LLM holds the GPU memory

WEAK SPOT    "Kill it" vs "stop it". A process systemd owns comes back if you
             kill it (Restart=always). Stop AND disable the UNIT instead.
             Also: a GPU can be "working" and still be full.
LOCAL-FIRST  Late alerts smell like network. They aren't: video is smooth,
             so the network is fine. The box is slow at DETECTING.

THE SHORT FORMS (this is all you type)
  nvidia-smi                   who holds the GPU, and how much memory
  sudo journalctl -u analytics -n 20      why analytics isn't on the GPU
  systemctl status PID         which UNIT owns a process
  ollama ps                    what model the LLM server has loaded
  sudo systemctl disable --now ollama     stop it now AND at boot
  sudo systemctl restart analytics        it picks a device only at start

## 1 OBSERVE
SAY: "Video is fine, so the network is fine. I'll check the analytics
      service and the GPU."
  $ systemctl status analytics
    => active (running): up, but that says nothing about the GPU
  $ nvidia-smi
    => Memory-Usage 10960MiB / 12288MiB
    => the Processes table has ONE row:
       153   C   /usr/local/bin/ollama runner   10960MiB
    => analytics is not in the list
  $ sudo journalctl -u analytics -n 20
    => -u = only this unit (service). -n 20 = the last 20 lines
    => CUDA init failed: CUDA_ERROR_OUT_OF_MEMORY: out of memory:
    => tried to allocate 1874 MiB (GPU 0; 12288 MiB total, 1328 MiB free)
    => falling back to CPU inference

## 2 NARROW
SAY: "Something else has the GPU's memory. I'll find out what owns that
      PID before I touch it."
  $ systemctl status 153
    => use the PID from nvidia-smi (yours will differ)
    => ollama.service - Ollama Service ... enabled
  $ systemctl cat ollama
    => prints the unit file and its drop-in (override.conf)
    => Restart=always: kill the PID and systemd starts it again in 3 s
    => override.conf: ExecStartPost ... ollama run llama3.1:8b
    => (it reloads the model every time it starts)
  $ ollama ps
    => llama3.1:8b   ...   11 GB   100% GPU   Forever

## 3 ACT
SAY: "The pilot is rolled back, so this service shouldn't be running.
      I'll stop and disable it, but not uninstall it. Then I restart
      analytics, because it only picks its device when it starts."
  $ sudo systemctl disable --now ollama
    => disable = do not start at boot. --now = and stop it right now
    => Removed ".../default.target.wants/ollama.service"
  $ sudo systemctl restart analytics

## 4 VERIFY
SAY: "Analytics should now be in the GPU process list, and the LLM
      should stay off."
  $ nvidia-smi
    => one process: .../python3 /opt/analytics/analytics.py   1874MiB
  $ systemctl is-enabled ollama
    => disabled
  $ tail -2 /var/log/analytics/detect.log
    => tail -2 = the last 2 lines
    => fps=24.0 device=cuda:0
  $ check

TRAP
  - `kill -9 PID`: Restart=always brings it back in 3 s and the model
    reloads. Watch nvidia-smi and the memory fills up again.
  - `ollama stop llama3.1:8b` frees the memory now, but the service is
    still enabled: it is back after the next reboot.
  - `systemctl stop` without disable: same, back at boot.
  - Stopping ollama but not restarting analytics: it is still on CPU.
  - Deleting the unit: the ticket said the AI team wants it later.

DO IT BETTER
  - Before killing a PID, ask who owns it: systemctl status PID.
  - disable --now = stop now + don't start at boot, in one command.
  - Say out loud what you're NOT doing: "not uninstalling, only off".
  - Tell the AI team: their model needs ~11 GB of a 12 GB card, so it
    can't run beside analytics on this box.
