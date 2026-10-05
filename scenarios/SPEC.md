# Scenario contract

One directory per scenario: `scenarios/<name>/`. The shared image is built once; a scenario is
selected at run time and bind-mounted read-only at `/drill` inside a fresh systemd container.

| file | runs as / when | purpose |
|---|---|---|
| `meta.env` | host, sourced | `TITLE` `LEVEL`(1-3) `TAGS`(space list) `LAB`(0/1) `DOCKER_ARGS`(extra `docker run` flags, no spaces inside a flag) `BOXNAME`(optional hostname, default edge-nvr-03) `PARKED`(1 = skipped by random/session unless `--tag` is given; still runs by name) |
| `ticket.txt` | shown on login and by `ticket` | ticket-style prompt. Symptoms only, no hints, no command names |
| `hints.txt` | `hint` | exactly 3 non-empty lines, escalating: (1) which class of problem, (2) which tool family, (3) almost the command |
| `break.sh` | **root**, once, after systemd is up (`bash -c 'set -e; . break.sh'`) | creates the broken state. Must be deterministic and *stable* by the time it returns (no races, no "it breaks in 20 s") |
| `check.sh` | **root**, on every `check` | `. /usr/local/lib/drill/lib.sh`; use `ok` `bad` `info` `want "desc" cmd...` and end with `finish`. Exit 0 only when really fixed |
| `solution.sh` | **tech** (sudo NOPASSWD) in `selftest` | the ideal fix as non-interactive code; exit 0. Use `sudo` where a real fix needs root |
| `solution.md` | shown by `solution` | Observe / Narrow / Act / Verify with `SAY:` narration lines (copy `adb-offline` or `disk-full`, 80 columns) |
| `mock/*` | read by break.sh from `/drill/mock/` | optional scenario-only mocks, e.g. docker-analytics' container workloads; keeps them out of break.sh and out of the shared image |
| `lab-box.sh` + `lab-side.sh` | optional. lab-box.sh: **root in the box**, before break.sh; lab-side.sh: **root in a sidecar container `<NS>-lab`** (own network namespace, `--network none`, scenario at `/drill`) | **The far end of a network drill (NOC host, hubs, cameras, AP clients) goes here, never on the box**: anything on the box shows up in `ps`, `ss`, `systemctl` and `grep -r /etc` and he chases it (09-29). lab-box.sh makes a veth pair and prints `LINK=<peer>` (moved into the sidecar) and any `KEY=VAL` lines (env for lab-side.sh); lab-side.sh sets its end up, starts the stand-in with `setsid -f`, waits until it listens, and may print `KEY=VAL` lines (env for break.sh). check.sh cannot reach the sidecar: check the far end over the network (a port answers, a reply seen on the wire), never its files. Box-side helper links are named `*-sim` |
| `traps/*.sh` | **root**, selftest only, on a fresh broken box | each is a plausible WRONG fix; `check` must still FAIL afterwards |

## Rules for check.sh
- Verify the *effect* (port answers, service active, file mode, process gone), not that a config line changed.
- Accept every legitimate fix (sed vs editor, `systemctl edit` vs unit edit, kill vs stop). Reject shortcuts
  (`chmod 777`, moving the port, deleting the thing, disabling the service that must run).
- Must FAIL on the untouched broken box and on each trap. Must be fast (< 10 s) and read-only apart from probes.
- Print what it saw on FAIL (`bad "X is still Y"`) but never the fix.

## solution.md shape
Copy `adb-offline` or `disk-full`. Every line <= 80 columns (`awk 'length>80'` prints nothing).
The in-box `solution` colours it by line type and pages it, so keep these line shapes exact:
```
# <name>: <title>

WEAK SPOT    <which common confusion this drills>
LOCAL-FIRST  <why no network tool is needed / when it is>

THE SHORT FORMS (this is all you type)
  <command>                    <what it's for>

## 1 OBSERVE
SAY: "<what to say out loud, wrapped with 6-space
      continuation lines>"
  $ <command, verbatim; long ones break with \ + 6-space indent>
    => <what you see: one => line per annotation, never on the $ line>
## 2 NARROW / ## 3 ACT / ## 4 VERIFY   same shape

TRAP
  - <the tempting wrong move and why it fails>

DO IT BETTER
  - <the habit to keep>
```
SHORT FORMS and DO IT BETTER use only commands already in that scenario's solution.md or solution.sh.
**Commands a human types.** The learner is not a flag expert. Use the plainest command that reaches the
answer, and narrow with `| grep` instead of filters: `sudo ss -tlnp | grep 8080` (never `'sport = :8080'`),
`ps aux | grep NAME` (never `ps -o ... -p`), plain `nvidia-smi` (never `--query-*`), `docker inspect C | grep -i X`
(never Go templates). No `xargs`, avoid `$(...)` and awk unless the drill is about them. Explain every flag the first
time it appears, on a `=>` line (`=> -t TCP  -l listening  -n numbers  -p program`). hints.txt line 3 names the
commands AND says what each flag does.
Multi-line config (logrotate, a unit drop-in) is written out as a real block, never one line.

## Coaching targets (design tickets around these)
- df vs du vs fdisk: fdisk is never the answer to "disk full".
- `lsof` (never "ldisk"), `ss -ltnp`, `fuser`. `kill` is not `rfkill`; TERM first, then -9.
- At least one ticket per author should *smell like network* while the fault is local.
- Real-world flavour: new-install support at facilities: cameras, NVR/edge boxes, a GPU analytics box,
  a Qualcomm SoC device. Box `edge-nvr-03`, site "Northgate Garage", user `tech`.

## Environment facts (learned the hard way)
- PID 1 is real systemd (Debian 12). `systemctl`, `journalctl`, `sshd` (unit `ssh`, alias `sshd`) are real.
- No internet reliance in any check. No reboots. `dmesg` is not readable. `free`, `uptime`, `nproc`
  and `df /` show HOST values: do not build a scenario on them. Container: 1 CPU, 512 MB, NET_ADMIN, SYS_PTRACE.
- To make a small full filesystem use `DOCKER_ARGS="--tmpfs /var/log:rw,size=48m,mode=0755"`
  (inodes: add `nr_inodes=N`). `/run` and `/tmp` are tmpfs.
- `/etc/resolv.conf`, `/etc/hosts`, `/etc/hostname` are Docker bind mounts: `sed -i` on them fails (EBUSY).
- Shared baseline service: `/usr/local/lib/drill/analytics-install [--no-start]` creates user `analytics`,
  `/etc/analytics/analytics.conf`, `analytics.service` (runs `/opt/analytics/analytics.py`, a fake video-analytics
  daemon, optional `EnvironmentFile=-/etc/default/analytics`) and enables it. It falls back to CPU if another live
  `/run/mock-gpu/*.json` holder leaves < 1874 MiB of the 12288 MiB card free (see gpu-vram-llm). Read `image/rootfs/opt/analytics/analytics.py`.
- Mock `nvidia-smi` and `lspci` live in `image/rootfs/usr/local/bin/`. Thermal/power knob: `/run/mock-gpu/card.state`
  (JSON `power_limit`, `fan_max`, overrides `fan temp power_draw clock_sm reasons`); `nvidia-smi -pl W` (root) sets it,
  `-q [-d PERFORMANCE,POWER,TEMPERATURE,CLOCK]` shows Clocks Event Reasons; analytics follows the SM clock. No file =
  the old fixed values. See chain-gpu-thermal. The analytics daemon writes
  `/run/mock-gpu/analytics.json` while it "holds" the GPU; `nvidia-smi` lists it in the process table.
- Installed: iproute2 iputils-ping traceroute dnsutils nc curl tcpdump iptables lsof psmisc procps strace fdisk rfkill
  sshd sudo logrotate cron python3 vim-tiny nano less dnsmasq isc-dhcp-client (`dhclient`) iputils-arping.
  NOT installed on purpose: net-tools, parted, htop.
- Shared mock Docker: `/usr/local/lib/drill/docker-install [--no-start]` installs `/usr/local/bin/docker` (CLI 27.3.1 +
  compose v2.29), `/usr/bin/dockerd`, `docker.service` (in /usr/lib, maskable), group `docker`, the nvidia runtime in
  `/etc/docker/daemon.json`; starts it and waits for the socket. Mock needs root: solutions say `sudo docker`.
  Add an image: `/etc/mock-docker/images.d/<x>.json` = `{"repo:tag": {"kind": "K", "size": "1.2GB", "age": 864000,
  "cmd": [...], "env": [...]}}` (all optional but kind). Its process: `/usr/local/lib/mock-docker/K/__main__.py`, run as
  `python3 -m K`; it appends docker json-file lines to `$MOCKD_LOG` (copy `docker-analytics/mock/rtsprelay.py`); its
  exit code is recorded. No such dir = one-shot image. Restart policies are real: dockerd restarts a dead container
  (100 ms backoff doubling to 60 s), `docker ps` shows `Restarting (1) 5 seconds ago`. Env knobs on `run`/`compose up`:
  `MOCK_DOCKER_BACKDATE=svc=SECONDS` (compose: created that long ago), `MOCK_DOCKER_RESTARTS=name=N` (already
  crash-looped N times, backoff at max). Works: ps [-a], logs [-f --tail --since -t], inspect (+ `| grep`), run, exec
  (single commands), start/stop/restart/rm, top, stats, images / image ls, rmi / image rm, image prune [-a], system df,
  system prune, info, version; compose up [-d] / ps / logs / restart / stop / start / down / config / ls.
  Workloads also get `MOCKD_BINDS` (JSON list of "host:container:mode") and `MOCKD_CMD`. Disk drills: an image
  with `"disk": "24MB"` really occupies those bytes under /var/lib/docker/overlay2 once pulled (`docker pull`,
  compose up/run pull a missing one); `"remote": true` = in the registry only; key `"sha256:<id>"` + `"dangling": true`
  = a <none> image; `"ref": null` drops a built-in. rmi / image prune / system prune delete the bytes, system df counts
  them (not logs, like the real one). Pull on a full fs fails `no space left on device`. json-file logs honour
  max-size/max-file from daemon.json `log-opts` (read when dockerd STARTS, applied at container CREATE), compose
  `logging:` or `run --log-opt`; dockerd rotates them, `docker logs` reads the rotated files, inspect shows LogConfig.
  A bad daemon.json stops dockerd ("unable to configure the Docker daemon"). See docker-disk-full.
- Lived-in box (opt-in, new scenarios only): `/usr/local/lib/drill/lived-in [--no-failed] [--no-ssm]` adds idle healthy
  `amazon-ssm-agent`, `prometheus-node-exporter` (:9100) and `grafana-agent` (127.0.0.1:12345), a `fwupd-refresh.timer`,
  boot noise in the journal (kernel taint/USB-serial, ntpdate, one WARN per agent) and, unless `--no-failed`, a FAILED
  `fwupd-refresh.service` ("Could not resolve hostname": a red herring; use `--no-failed` in a DNS drill; `--no-ssm` if the scenario installs its own agent). The journal
  is volatile, so noise is stamped at boot. < 1 s. Call it in break.sh; check.sh must not depend on it.
- `ss -p`/`lsof` see other users' processes only as root, and `journalctl` shows a normal user nothing useful (needs `sudo`):
  realistic, so write `sudo journalctl` in solutions.
- sshd: `Port` lines ACCUMULATE across the main file and `sshd_config.d/*.conf` (most other keywords are first-match-wins).
  `/run/sshd` vanishes when `ssh.service` is stopped/failed, after which `sshd -t`/`-T` complain about privilege separation.
- `boot()` waits for systemd to finish booting before running break.sh; a break.sh that starts many units should still wait for its own jobs.

## Testing
`./drill.sh selftest <name>...` boots a fresh container per phase: check must FAIL when broken, must FAIL after each
`traps/*.sh`, and must PASS after `solution.sh`. Debug interactively with
`DRILL_NS=dbg-me ./drill.sh up <name>` then `docker exec -it -u tech dbg-me bash -l`; remove with `docker rm -f dbg-me`.
Never run `./drill.sh clean` while other scenarios are being tested.
- Units you want to `systemctl mask` must live in `/usr/lib/systemd/system` (masking a unit that has a file in `/etc/systemd/system` fails with "File exists").
- `DRILL_NS=<name>` gives a debug/selftest container its own name; `selftest` names its boxes `drillst-<pid>-<scenario>`, so it can run beside a live drill and beside another selftest (only the lab is shared).
