# docker-disk-full: nightly update dies "no space left on device"

WEAK SPOT    df vs du vs docker system df. df = WHICH filesystem is full,
             du = WHAT fills it, docker system df = images only: it
             does NOT count container logs.
LOCAL-FIRST  Local. The recordings disk is a different filesystem and
             is not full.

THE SHORT FORMS (this is all you type)
  df -h                               which filesystem is at 100%
  sudo du -h -d1 /var/lib/docker      images (overlay2) or logs?
  sudo du -h -d1 /var/lib/docker/containers   which container's log
  sudo docker system df               Docker's view of image space
  sudo docker images                  old tags, <none> leftovers
  sudo docker inspect event-uploader | grep -A3 LogConfig   a limit?
  sudo docker image prune             delete dangling (<none>) images
  sudo docker rmi IMAGE:TAG           delete one old version
  sudo nano /etc/docker/daemon.json   add log-opts
  sudo systemctl restart docker       dockerd reads daemon.json
  sudo docker compose up -d --force-recreate   new containers, new limits

## 1 OBSERVE
SAY: "The update says no space. First: which filesystem, and did
      anything else fail?"
  $ systemctl --failed
    => fwupd-refresh.service: firmware metadata, no internet here.
       Unrelated, dismissed.
  $ tail -3 /var/log/edge-update.log
    => pulling registry.local/edge/vehicle-count:2.5.0
    => ERROR docker pull: failed to register layer: write
       /var/lib/docker/overlay2/...: no space left on device
  $ df -h
    => -h = human sizes (M, G)
    => tmpfs  160M  160M  0  100% /var/lib/docker     <- full
    => tmpfs   64M   37M 28M  58% /srv/nvr            (recordings: fine)
    => "/" shows the host's disk in this drill: ignore it
SAY: "Recordings have room. Docker's own filesystem is full."

## 2 NARROW
SAY: "Images or logs? du adds up what is really on disk."
  $ sudo du -h -d1 /var/lib/docker
    => -d1 = one level deep: a total per folder
    => 131M /var/lib/docker/overlay2     (image layers)
    => 30M  /var/lib/docker/containers   (container logs)
    => (sudo du /var/lib/docker/* fails: the * is expanded by MY
       shell, which can't read that root-only folder)
  $ sudo docker system df
    => Images 9 ... 136.7MB  98.4MB (71%) reclaimable
    => Containers ... 0B: logs are NOT counted here, only du sees them
  $ sudo docker images
    => three <none> <none> images: old event-uploader layers left
       behind each time :stable was re-pulled (dangling)
    => vehicle-count 2.4.1 (running), 2.4.0 (the rollback: KEEP),
       2.3.9 and 2.3.8 (older than the rollback)
  $ sudo du -h -d1 /var/lib/docker/containers
    => 29M /var/lib/docker/containers/f5e72ced0497...
  $ sudo docker ps
    => f5e72ced0497 ... event-uploader   (same ID start: its log)
  $ sudo docker inspect event-uploader | grep -A3 LogConfig
    => -A3 = also the 3 lines after the match
    => "Type": "json-file", "Config": {}   <- no max-size: no limit
  $ sudo docker logs --tail 2 event-uploader
    => DEBUG uploader: poll cam06 queue=0 ... ten times a second
SAY: "Two causes: leftover images, and a debug log with no cap."

## 3 ACT
SAY: "Free space without touching 2.4.0, then cap the logs so it
      can't come back."
  $ sudo docker image prune
    => prune = delete unused things. Without -a: only dangling images
    => answer y. "Total reclaimed space: 27.7MB"
  $ sudo docker rmi registry.local/edge/vehicle-count:2.3.8 \
      registry.local/edge/vehicle-count:2.3.9
    => rmi = remove image. Untagged ... Deleted ...
  $ sudo nano /etc/docker/daemon.json
    => keep the "runtimes" block; add a comma after its closing }
       and then:
      "log-driver": "json-file",
      "log-opts": {
          "max-size": "10m",
          "max-file": "3"
      }
    => 10m x 3 = at most 30 MB of log per container. No comma after
       the last entry: a stray comma and dockerd won't start
  $ sudo systemctl restart docker
    => dockerd only reads daemon.json when it starts
  $ cd /opt/edge
  $ sudo docker compose up -d --force-recreate
    => log settings are fixed when a container is CREATED, so make
       new ones. --force-recreate = even if compose.yaml is unchanged
    => the old event-uploader and its 29M log go with it

## 4 VERIFY
SAY: "Space is back, the rollback is still there, and the new
      container has a cap."
  $ df -h /var/lib/docker
    => tmpfs 160M ... 38% /var/lib/docker
  $ sudo docker images
    => 2.4.1 and 2.4.0 still listed, no <none> lines
  $ sudo docker inspect event-uploader | grep -A5 LogConfig
    => "max-size": "10m", "max-file": "3"
  $ check

TRAP
  - docker system prune -a: "unused" includes 2.4.0, the rollback
    image nobody runs. Read what -a means before you type it.
  - rm -rf /var/lib/docker: every image and container gone.
  - Only truncating the log: back to 100% in a day or two.
  - daemon.json + restart docker, but no recreate: running containers
    keep the settings they were created with (inspect shows Config {}).
  - A stray comma in daemon.json: docker won't start at all
    (sudo journalctl -u docker shows "unable to configure").
  - Deleting recordings: a different disk, and not full.

DO IT BETTER
  - df first (which fs), du second (what), docker system df third
    (and remember it ignores logs).
  - Every box gets default log-opts in daemon.json on day one.
  - ESCALATE / TELL THE VENDOR: "event-uploader:stable ships with
    debug logging and no log limit; it filled /var/lib/docker. Capped
    logs at 10m x 3, removed 2.3.8/2.3.9 and dangling images, kept
    2.4.0 for rollback. Tonight's 2.5.0 update now has room."
