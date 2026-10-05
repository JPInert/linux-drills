# rtsp-stream-auth: 'stream unavailable', the camera refuses the login

WEAK SPOT    "Video is down, so it's the network." Read the status code
             first: 401 means the camera GOT the request and refused WHO
             asked. That is a login, not a cable or a port.
LOCAL-FIRST  RTSP sets up the session; RTP carries the video. The session
             never gets past DESCRIBE, so no video ever starts. One nc
             proves the port, then the box's own journal says why.

THE SHORT FORMS (this is all you type)
  sudo journalctl -u stream-ingest | tail     what the camera answers
  nc -zv 10.50.1.31 554        is the RTSP port open (network test)
  curl -v rtsp://10.50.1.31/Streaming/Channels/101
                               does the camera speak RTSP at all
  curl -v --user nvr:PASS rtsp://10.50.1.31/Streaming/Channels/101
                               is this login accepted (401 or 200)
  sudo cat /etc/stream-ingest/ingest.conf     the login the service sends
  cat ~/install-sheet.txt                     the login it SHOULD send
  sudo nano /etc/stream-ingest/ingest.conf    fix CAMERA_PASS (keeps 0640)
  sudo systemctl restart stream-ingest        it reads its config at start

## 1 OBSERVE
SAY: "The web page loads, so the path to the camera works. I'll ask
      the service that pulls the stream what the camera tells it."
  $ systemctl status stream-ingest
    => Active: active (running): up, but that says nothing about the camera
  $ sudo journalctl -u stream-ingest | tail
    => -u = only this service's log   tail = only the last 10 lines
    => camera1: DESCRIBE rtsp://10.50.1.31:554/Streaming/Channels/101
       -> RTSP/1.0 401 Unauthorized
    => camera1: stream unavailable, retry in 3s
  $ cat /run/stream-ingest/status
    => "last": "RTSP/1.0 401 Unauthorized", "stream": "unavailable"

## 2 NARROW
SAY: "401 is an answer from the camera. First I'll prove the port,
      so nobody sends a tech to check a cable."
  $ nc -zv 10.50.1.31 554
    => nc tries to open a connection to a port, like a client would
    => -z = just connect, send nothing   -v = say what happened
    => Connection to 10.50.1.31 554 port [tcp/rtsp] succeeded!
  $ curl -v rtsp://10.50.1.31/Streaming/Channels/101
    => -v = show the whole conversation: > = what curl sent,
       < = what the camera answered
    => > OPTIONS * RTSP/1.0
    => < RTSP/1.0 200 OK
    => < Public: OPTIONS, DESCRIBE, SETUP, PLAY, PAUSE, TEARDOWN, ...
    => the camera speaks RTSP (curl only sends OPTIONS: no login needed)
SAY: "The port and RTSP are fine. Which login does the service send,
      and what does the install sheet say?"
  $ sudo cat /etc/stream-ingest/ingest.conf
    => CAMERA_USER=nvr
    => CAMERA_PASS=Nvr2024-HR09     (rotated by site IT)
  $ cat ~/install-sheet.txt
    => camera1 stream  rtsp://10.50.1.31:554/Streaming/Channels/101
    => user nvr   password HR-cam1-4471   (install value)
SAY: "The firmware update put the camera back to the install-sheet
      password. I'll prove both logins against the camera."
  $ curl -v --user nvr:Nvr2024-HR09 \
      rtsp://10.50.1.31/Streaming/Channels/101
    => --user USER:PASSWORD = log in with this
    => \ at the end of a line = the command continues on the next one
    => < RTSP/1.0 401 Unauthorized
    => < WWW-Authenticate: Basic realm="camera1"
  $ curl -v --user nvr:HR-cam1-4471 \
      rtsp://10.50.1.31/Streaming/Channels/101
    => < RTSP/1.0 200 OK        <- the sheet's login is the live one

## 3 ACT
SAY: "I'll change only the password, in the same file, so it keeps its
      owner and mode: it holds a camera password. Then restart the
      service, because it reads its config only at start."
  $ sudo nano /etc/stream-ingest/ingest.conf
    => change CAMERA_PASS=Nvr2024-HR09 to CAMERA_PASS=HR-cam1-4471
    => save (Ctrl+O, Enter), quit (Ctrl+X)
    => the same edit in one line, no editor:
       sudo sed -i 's/^CAMERA_PASS=.*/CAMERA_PASS=HR-cam1-4471/' FILE
       (-i = change the file in place; s/old/new/ = replace old with new)
  $ ls -l /etc/stream-ingest/ingest.conf
    => -l = long listing: permissions, owner, group, size, date
    => -rw-r----- 1 root ingest ...   (0640 root:ingest, unchanged)
  $ sudo systemctl restart stream-ingest

## 4 VERIFY
SAY: "The proof is what the camera answers the SERVICE, not me."
  $ sudo journalctl -u stream-ingest | tail -3
    => tail -3 = only the last 3 lines
    => stream-ingest 1.3 starting: camera1 rtsp://10.50.1.31:554/...
    => camera1: DESCRIBE rtsp://10.50.1.31:554/... -> RTSP/1.0 200 OK
  $ cat /run/stream-ingest/status
    => "last": "RTSP/1.0 200 OK", "stream": "up"
  Tell site IT the update reset the password: any future rotation must
  change the camera AND this config together
  $ check

TRAP
  - Sending someone to check the switch or cable: nc to 554 succeeds
    and the camera answers 401. The network is fine.
  - `curl -v rtsp://...` WITHOUT --user says 200: it only sent OPTIONS,
    which needs no login. It proves RTSP is alive, not the password.
  - Restarting the service alone: it reads the same stale password.
  - Editing the file but not restarting: it still sends the old one.
  - `chmod 777` on the config: every user can read the camera password,
    and the service refuses to start from a world-readable config.
  - The "older firmware" path in the config comment: that URL is 404 on
    this camera. The path was never the problem; the 401 said so.
  - Pointing the service at another address: only camera1 is the camera.

DO IT BETTER
  - Read the status code before blaming the network: 401 = who you
    are, 404 = what you asked for, no answer at all = network.
  - One nc -zv to the port settles "is it the network" in a second.
  - Edit configs that hold secrets in place (sudo nano, sed -i) and
    check ls -l after: owner root, group of the service, nothing for
    others.
