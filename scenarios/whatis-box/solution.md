# whatis-box: new site handover, what is this box running?

WEAK SPOT    on a box you have never seen, the first five minutes are a
             sweep, not a guess: GPU, services, failed units, ports,
             config. Each question has its own command.
LOCAL-FIRST  Everything is local. Install notes go stale: the box itself
             is the source of truth.

THE SHORT FORMS (this is all you type)
  nvidia-smi                   GPU model, total memory, who is using it
  systemctl list-units --type=service | grep running
                               what services are running
  systemctl --failed           anything in a failed state
  sudo ss -tlnp                every listening TCP port + its program
  sudo grep -E 'CAMERAS|MODEL' /etc/analytics/analytics.conf
                               what analytics is configured for
  ls -l /opt/analytics/models  the model files on disk, with dates
  answer "gpu=... vram=... cams=... web=... failed=... model=..."

## 1 OBSERVE
SAY: "New box. I'll sweep it top-down: the GPU, the services, the ports,
      then the config, and write each fact down as I go."
  $ nvidia-smi
    => NVIDIA RTX A2000 12GB           <- the model: gpu=A2000
    => 1874MiB / 12288MiB              Memory-Usage = used / TOTAL:
                                       vram=12288 (the card), not 1874
    => Processes: .../opt/analytics/analytics.py 1874MiB: analytics is
       on the GPU
  $ systemctl list-units --type=service | grep running
    => --type=service = only services (not mounts, sockets, timers)
    => analytics, nvr-web, ssh, amazon-ssm-agent, grafana-agent,
       prometheus-node-exporter, plus systemd's own
  $ systemctl --failed
    => fwupd-refresh.service  loaded failed failed  <- failed=
    => a firmware check that can't reach the internet: harmless here,
       but it is on the list you hand over

## 2 NARROW
SAY: "Now what listens, and who is behind each port."
  $ sudo ss -tlnp
    => -t TCP  -l listening  -n numbers (not names)  -p program
    => (without sudo, -p shows no program for other users' services)
    => the Process column names the program behind each port:
    => 0.0.0.0:7001      "nvr-web"         <- web=7001 (yours differs)
    => 0.0.0.0:22        "sshd"            ssh, not the web UI
    => *:9100 "prometheus-node", 127.0.0.1:12345 "grafana-agent":
       monitoring agents, not the web UI either
  $ sudo grep -E 'CAMERAS|MODEL' /etc/analytics/analytics.conf
    => -E = extended pattern: | means OR, so either word matches
    => (without sudo: Permission denied, the file is root:analytics)
    => CAMERAS=12                                   <- cams=12
    => MODEL=/opt/analytics/models/bed-exit-v2.engine   <- model=
  $ ls -l /opt/analytics/models
    => -l = long listing: size and date
    => vehicle-count-v2.9.engine is the NEWEST (an hour ago): a staged file
       nobody switched to. The config, not the date, says what loads
    => person-vehicle.engine, 0 bytes: the install default, unused

## 3 ACT
SAY: "Six facts, each from the command that owns it."
  $ answer "gpu=A2000 vram=12288 cams=12 web=7001 \
      failed=fwupd-refresh model=bed-exit-v2.engine"
    => use YOUR values: cams, web and model change every run

## 4 VERIFY
  $ check

TRAP
  - Copying the install notes (4 cameras, port 8080, person-vehicle):
    stale by definition.
  - vram=1874: that is the memory IN USE; the card's total is 12288.
  - web=22 or 9100: sshd and the node exporter also listen; read the
    program name on the line, not just the port.
  - The newest model file is a staged one; only the config says what
    analytics loads.

DO IT BETTER
  - One sweep, in order: nvidia-smi, systemctl (running and --failed),
    sudo ss -tlnp, then the service's own config.
  - Trust the box over the notes, and the config over file dates.
  - ESCALATE / TELL THE CUSTOMER: hand over the six facts, and flag the
    failed fwupd-refresh and the staged model so nobody is surprised
    by them on the go-live call.
