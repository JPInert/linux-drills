# docker-analytics: fall alerts late, the container lost its GPU

WEAK SPOT    "Running" is not "working", and restart is not recreate. A
             container keeps the config it was CREATED with: restart
             reuses it. Only `compose up -d` rebuilds it from the file.
LOCAL-FIRST  Late alerts smell like network. They aren't: video is smooth,
             so the cameras and the network are fine. The box is slow at
             DETECTING. No network tool needed.

THE SHORT FORMS (this is all you type)
  sudo docker ps               what runs, since when (you're not in docker)
  sudo docker logs vehicle-count | head        what it said at start
  nvidia-smi                   is ANYTHING on the GPU?
  sudo docker inspect vehicle-count | grep DeviceRequests
                               did the container get a GPU? (null = no)
  cd /opt/vehicle-count          the folder with compose.yaml in it
  diff compose.yaml.2.3.8.bak compose.yaml   what the update changed
  sudo nano compose.yaml       put the GPU block back
  sudo docker compose config -q              check the file (no output = ok)
  sudo docker compose up -d    recreate from the file (NOT restart)

## 1 OBSERVE
SAY: "Video is fine, so the network is fine. The detector is slow. I'll
      look at the containers and at the GPU."
  $ docker ps
    => permission denied while trying to connect to the Docker daemon
       socket at unix:///var/run/docker.sock
    => tech is not in the docker group. Use sudo.
  $ sudo docker ps
    => vehicle-count:2.4.1   ...   Up 14 hours   (recreated by the update)
    => rtsp-relay:1.9.2    ...   Up 9 days     (the video path, untouched)
  $ sudo docker logs vehicle-count | tail -3
    => logs = everything the container has printed; tail -3 = last 3
    => stats ... device=cpu alert_latency_ms=28106
    => WARN alert latency 28.1s over SLO 2.0s (frames are queuing)
    => (two torch "UserWarning" lines also show up above it: the app
       printed them as errors, which the pipe does not filter)
  $ sudo docker logs vehicle-count | head
    => head = the first 10 lines: what it said when it started
    => vehiclecount 2.4.1 starting ...
    => WARN CUDA not available, falling back to CPU (expect ~10x slower
       inference)
    => CUDA = the GPU; so it is running the model on the CPU
  $ nvidia-smi
    => NVIDIA RTX A2000 12GB ... 0MiB / 12288MiB
    => the GPU and driver answer fine, but: No running processes found

## 2 NARROW
SAY: "The host sees the GPU, the container doesn't. So it's how the
      container was created, not the driver. I'll check its GPU request."
  $ sudo docker inspect vehicle-count | grep DeviceRequests
    => inspect prints the container's full settings (about 150 lines);
       grep picks the one line about devices it asked for
    => "DeviceRequests": null      no GPU was asked for at creation
  $ sudo docker exec vehicle-count nvidia-smi
    => exec = run a command INSIDE the container
    => exec: "nvidia-smi": executable file not found in $PATH
    => (the NVIDIA runtime only puts it into containers given a GPU)
  $ cat /var/log/edge-update.log
    => backed up /opt/vehicle-count/compose.yaml -> compose.yaml.2.3.8.bak
    => wrote /opt/vehicle-count/compose.yaml from bundle template
  $ cd /opt/vehicle-count
  $ ls
    => compose.yaml  compose.yaml.2.3.8.bak  models
  $ diff compose.yaml.2.3.8.bak compose.yaml
    => diff OLD NEW: < = only in the old file, > = only in the new one
    => < image: registry.local/edge/vehicle-count:2.3.8
    => > image: registry.local/edge/vehicle-count:2.4.1     (wanted)
    => 20,26d19
    => <     deploy:
    => <       resources: ...  - driver: nvidia ... capabilities: [gpu]
    => the whole deploy: block (7 lines) is gone (not wanted)

## 3 ACT
SAY: "I keep 2.4.1 and put the GPU reservation back in the compose file.
      Then I recreate with compose, because restart keeps the old config."
  $ sudo nano compose.yaml
  Under `vehicle-count:`, at the same indent as `image:`, add back:
      deploy:
        resources:
          reservations:
            devices:
              - driver: nvidia
                count: all
                capabilities: [gpu]
  Spaces, not tabs: YAML cares about the indent.
  Also valid: `runtime: nvidia` (the runtime is registered: docker info).
  $ sudo docker compose config -q
    => config = read and check compose.yaml   -q = quiet
    => no output = the file is valid (a bad indent prints an error)
  $ sudo docker compose up -d
    => up = make the containers match the file   -d = in the background
    => Container rtsp-relay  Running    (unchanged, left alone)
    => Container vehicle-count  Recreate ... Recreated ... Started
    => if it only says Running for both, the file did not change

## 4 VERIFY
SAY: "It should be on the GPU now and the alert latency back under the
      SLO. Video was never touched."
  $ nvidia-smi
    => in the Processes table:  python3 -m vehiclecount   2410MiB
  $ sudo docker inspect vehicle-count | grep -A3 DeviceRequests
    => -A3 = also show the 3 lines After the match
    => "DeviceRequests": [ { "Driver": "nvidia", "Count": -1, ...
  $ sudo docker logs vehicle-count | grep -i cuda
    => grep -i = ignore upper/lower case
    => CUDA device 0: NVIDIA RTX A2000 12GB (compute 8.6, ...)
    => TensorRT engine loaded on cuda:0 (2410 MiB), batch=6
  $ sudo docker logs vehicle-count | tail -3
    => (after ~30 s) stats ... device=cuda:0 alert_latency_ms=450
  $ check

TRAP
  - `docker restart vehicle-count`: same container, same config, still CPU.
  - `docker compose restart`: also does not re-read compose.yaml.
  - Fixing the file, then restarting: file right, container still old.
  - `docker run --gpus all` by hand: works now, but it is outside
    compose; the next `compose up` or update throws it away.
  - FD_DEVICE=cpu: hides the warning, the alerts stay 25 s late.
  - Copying the .bak over the file: GPU back, but you rolled back to
    2.3.8, which the ticket said not to do.

DO IT BETTER
  - Container up and slow? Check the device first: nvidia-smi, then
    docker logs. "Up 14 hours" says nothing about the GPU.
  - Changed the compose file? `compose config -q`, then `up -d`.
  - Prove the layers: host nvidia-smi, then a throwaway test container
    given the GPU, then the app container. Where it stops is the fault:
      sudo docker run --rm --gpus all nvidia/cuda:12.2.0-base-ubuntu22.04 \
        nvidia-smi -L
    (--rm = delete it when done, --gpus all = give it the GPU,
     -L = just list the GPUs: GPU 0: NVIDIA RTX A2000 12GB ...)
  - Tell the vendor: their 2.4.1 bundle template drops the GPU stanza,
    so every box they update goes to CPU.
