# chain-docker-crashloop: no fall alerts since 3 AM, container crash loop

WEAK SPOT    "Online" and "running" are not "working". A container that
             starts, dies and restarts every minute looks alive from far
             away. docker ps -a says Restarting; the log says why.
LOCAL-FIRST  Local. The flaky camera is real but has nothing to do with
             zero alerts from every camera.

THE SHORT FORMS (this is all you type)
  systemctl --failed                     anything dead? (sweep)
  sudo docker ps -a                      Up? Exited? Restarting?
  sudo docker logs --tail 8 vehicle-count  its last words before dying
  sudo docker inspect vehicle-count | grep -A3 Binds   host dir of /models
  ls /opt/vehicle-count/models/v8.1/       what is really in that folder
  cat /var/log/edge-update.log           what the update did at 03:00
  sudo nano /opt/vehicle-count/compose.yaml     fix FD_MODEL
  cd /opt/vehicle-count                    the compose project folder
  sudo docker compose up -d              recreate from the fixed file

## 1 OBSERVE
SAY: "No alerts at all, but video and the NOC are fine. The sweep
      first, then the detector's containers."
  $ systemctl --failed
    => fwupd-refresh.service failed: it can't reach the internet to
       refresh firmware metadata. Nothing to do with alerts.
  $ sudo docker ps -a
    => -a = all containers, including stopped and restarting ones
    => vehicle-count   Restarting (1) 12 seconds ago    <- this
    => rtsp-relay    Up 9 days                        (the video)
    => "Restarting (1)": it exited with code 1 and docker's restart
       policy is starting it again, over and over
  $ sudo docker logs --tail 8 vehicle-count
    => --tail 8 = only the last 8 lines
    => FileNotFoundError: [Errno 2] No such file or directory:
       '/models/fall-pose-v8.1.engine'
    => FATAL ... cannot load model ... exiting (code 1)
  $ sudo docker logs --tail 4 rtsp-relay
    => WAR [path cam04] ... RTP packets lost ... reconnecting in 2s
    => ready: 1 track: one camera's link flaps and recovers. That is
       the "glitchy camera", and it can't stop alerts from all six.
       Red herring: note it for the site, move on.

## 2 NARROW
SAY: "/models is a path inside the container. Which host folder is it?"
  $ sudo docker inspect vehicle-count | grep -A3 Binds
    => -A3 = also print the 3 lines after the match
    => "/opt/vehicle-count/models/v8.1:/models:ro"
    => HOST:CONTAINER: /models is /opt/vehicle-count/models/v8.1
  $ ls /opt/vehicle-count/models/v8.1/
    => fall-pose-v8.1-fp16.engine   fall-pose-v8.1-fp16.onnx
       manifest.json
    => the file is called ...-fp16.engine. The container asks for
       fall-pose-v8.1.engine: no such file
  $ cat /opt/vehicle-count/models/v8.1/manifest.json
    => "engine": "fall-pose-v8.1-fp16.engine"   (the package agrees)
  $ cat /var/log/edge-update.log
    => 03:01 "unpacked fall-pose 8.1 to /opt/vehicle-count/models/v8.1/"
    => "wrote /opt/vehicle-count/compose.yaml from bundle template"
    => "health: container vehicle-count state=restarting" and then
       "update complete": the updater saw it and shipped it anyway
  $ grep -n FD_MODEL /opt/vehicle-count/compose.yaml
    => -n = show line numbers
    => 29:      - FD_MODEL=/models/fall-pose-v8.1.engine
SAY: "The template names the model without -fp16. The file is fine,
      the compose file points past it."

## 3 ACT
SAY: "I fix the name in the compose file and recreate the container.
      No rollback: the new model is what the site wants."
  $ sudo nano /opt/vehicle-count/compose.yaml
    => change  FD_MODEL=/models/fall-pose-v8.1.engine
       to      FD_MODEL=/models/fall-pose-v8.1-fp16.engine
    => Ctrl-O Enter saves, Ctrl-X quits
  $ cd /opt/vehicle-count
  $ sudo docker compose up -d
    => up = create/update containers from compose.yaml
    => -d = detached: start them in the background, give me my prompt
    => Container vehicle-count  Recreated ... Started
    => restart would NOT help: it reuses the container's old settings

## 4 VERIFY
SAY: "Proving it stays up and loaded the new model, not just that it
      started once."
  $ sudo docker ps
    => vehicle-count   Up 20 seconds   (run it again: the time keeps
       growing, no more Restarting)
  $ sudo docker logs --tail 5 vehicle-count
    => TensorRT engine loaded on cuda:0 ... fall-pose 8.1 fp16
    => rtsp: 6/6 streams connected ... stats ... device=cuda:0
  $ nvidia-smi
    => python3 -m vehiclecount listed with ~2630MiB: it is on the GPU
  $ check

TRAP
  - docker restart / docker compose restart: same config, same crash.
  - Rolling back to compose.yaml.2.4.1.bak or the v7 model: alerts
    come back, but the ticket said stay on the new release and model.
  - restart: "no" stops the loop by leaving the detector dead, and it
    stays dead after a reboot.
  - docker rm, or a hand-made docker run: the next compose up or
    update undoes it.
  - Chasing cam04: one flaky camera can't silence all six.

DO IT BETTER
  - docker ps -a, not docker ps: a crash loop hides between "Up" rows.
  - Map every path in an error to the host: inspect | grep -A3 Binds.
  - After the fix, look twice: "Up 5 s" then "Up 40 s" = not looping.
  - ESCALATE / TELL THE VENDOR: "2.5.0 compose template sets
    FD_MODEL=fall-pose-v8.1.engine but the 8.1 package ships
    fall-pose-v8.1-fp16.engine; fixed locally. Your updater reported
    'update complete' with the container restarting: its health gate
    is off on channel stable." Tell the site: cam04 link flaps.
