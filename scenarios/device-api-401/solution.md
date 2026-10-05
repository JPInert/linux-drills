# device-api-401: sensor hub data gone, every API poll gets 401

WEAK SPOT    Reading what an HTTP API actually said. The status code is the
             diagnosis:
               refused (curl: (7))  nothing listening on that port
               timeout (curl: (28)) no route, or a firewall drops it
               401  "who are you?"    token missing, wrong or revoked
               403  "I know you, no"  token fine, not allowed there
               404  wrong path or API version
               5xx  the far side broke: escalate to the vendor
LOCAL-FIRST  It smells like network ("the hub"), but the hub answers ping
             AND answers HTTP. A 401 is a reply: the network is fine,
             the credential is not.

THE SHORT FORMS (this is all you type)
  sudo journalctl -u hub-sync | tail -5   what the hub answers the client
  systemctl cat hub-sync                  which config file it reads
  sudo cat /etc/hub-sync/hub.env          URL + token (a secret: not in tickets)
  curl -ki URL                            status line + headers, no auth
  curl -ki -H "Authorization: Bearer TOKEN" URL      the same, with a token
  sudo nano /etc/hub-sync/hub.env         put the new token in
  sudo systemctl restart hub-sync         it reads hub.env only at start

## 1 OBSERVE
SAY: "Video and camera alerts still work, so it's just the hub's data.
      I'll find the service that talks to the hub and read its log."
  $ systemctl status hub-sync
    => Active: active (running): up, but that says nothing about the data
  $ sudo journalctl -u hub-sync | tail -5
    => -u = only this service's log   tail -5 = only the last 5 lines
    => WARNING poll failed: HTTP 401 {"error": "invalid_token", "detail":
       "token not recognised or revoked"}  (0 events forwarded)
    => a 401 is an ANSWER: the box reaches the hub, the hub says no

## 2 NARROW
SAY: "401 means authentication. I'll ask the hub myself, first with no
      token, then with the client's token, and compare."
  $ systemctl cat hub-sync
    => cat = print the unit file systemd is using
    => EnvironmentFile=/etc/hub-sync/hub.env   (its settings file)
  $ sudo cat /etc/hub-sync/hub.env
    => HUB_URL=https://10.60.0.20:8443/api/v2/events
    => HUB_TOKEN=... (a long hex string: the token the client sends)
    => it's a secret: fine on your console, never in a ticket or chat
  $ curl -k https://10.60.0.20:8443/api/v2/health
    => -k = accept the hub's self-signed certificate
       (without it: curl: (60) SSL certificate problem: self-signed)
    => {"status": "ok", ... "token_rotated_at": "2026-09-25T06:20:24Z"}
    => the hub is up, and it rotated its token in last night's window
  $ curl -ki https://10.60.0.20:8443/api/v2/events
    => -i = also show the reply's status line and headers
    => HTTP/1.1 401 Unauthorized
    => WWW-Authenticate: Bearer realm="sensor-hub"
    => {"error": "missing_token", ...}   fair: we sent none
  $ curl -ki -H "Authorization: Bearer OLDTOKEN" \
      https://10.60.0.20:8443/api/v2/events
    => -H = add a header; paste the HUB_TOKEN value from hub.env
    => \ at the end of a line = the command continues on the next one
    => HTTP/1.1 401 Unauthorized
    => {"error": "invalid_token", "detail": "token not recognised or
    => revoked"}: the client's token is dead
  $ ls -l /etc/hub-sync/
    => -l = long listing: permissions, owner, group, size, date
    => -rw-r----- 1 root hub-sync  49 Sep 25 06:20 token.new
    => dated last night: what the maintenance left behind
  $ sudo cat /etc/hub-sync/token.new
    => the new token (copy it)
  $ curl -ki -H "Authorization: Bearer NEWTOKEN" \
      https://10.60.0.20:8443/api/v2/events
    => HTTP/1.1 200 OK
    => {"hub": "SH-HR-02", ... "events": [{"sensor": "rm114-bed", ...
    => the new token works
SAY: "While I'm here, the other answers look different, so I'd know
      them next time."
  $ curl -ki -H "Authorization: Bearer NEWTOKEN" \
      https://10.60.0.20:8443/api/v2/admin/config
    => HTTP/1.1 403 Forbidden
    => {"error": "forbidden", "detail": "token scope events:read cannot
    => use admin"}: good token, not allowed there
  $ curl -ki -H "Authorization: Bearer NEWTOKEN" \
      https://10.60.0.20:8443/api/v1/events
    => HTTP/1.1 404 Not Found
    => {"error": "not_found", "detail": "API v1 was removed in fw 3.2 ..."}
  $ curl -k https://10.60.0.20:9443/
    => curl: (7) Failed to connect to 10.60.0.20 port 9443 after 0 ms:
    => Couldn't connect to server: nothing listens on :9443
  $ curl -k -m 3 https://10.60.0.21:8443/
    => -m 3 = give up after 3 seconds
    => curl: (28) Connection timed out after 3001 milliseconds
    => nothing answers at all: route or firewall
  $ curl --cacert /etc/hub-sync/hub.crt \
      https://10.60.0.20:8443/api/v2/health
    => --cacert FILE = trust this certificate instead of skipping checks
    => {"status": "ok", ...}: works WITHOUT -k; -k was only a shortcut

## 3 ACT
SAY: "The hub rotated the client token. I'll put the new one in the
      client's config without changing its permissions, then restart
      the client, because it reads the file only when it starts."
  $ sudo cat /etc/hub-sync/token.new
    => copy the token
  $ sudo nano /etc/hub-sync/hub.env
    => replace everything after HUB_TOKEN= with the new token
    => save (Ctrl+O, Enter), quit (Ctrl+X)
    => nano saves into the same file: owner and mode stay as they were
  $ ls -l /etc/hub-sync/hub.env
    => -rw-r----- 1 root hub-sync ...   (0640, as before)
  $ sudo systemctl restart hub-sync

## 4 VERIFY
SAY: "The client should now get 200s, and the token file should still
      be readable only by root and the service's group."
  $ sudo journalctl -u hub-sync | tail -3
    => hub-sync 1.4.2 starting: polling https://10.60.0.20:8443/...
    => poll ok: HTTP 200, 4 events forwarded to dashboard
  $ ls -l /etc/hub-sync/hub.env
    => -rw-r----- 1 root hub-sync   (0640, as before)
  $ check

TRAP
  - Restarting hub-sync without changing the token: it sends the same
    revoked token and gets the same 401.
  - Editing hub.env without a restart: the running process keeps the
    old token until it starts again.
  - chmod 644 / 777 on hub.env "so it can read it": the token is a
    secret, and the service reads it through systemd as root anyway.
  - Changing the URL to /api/v1: 404, v1 is gone. Or to /api/v2/health:
    200, but it carries no events, so the dashboard stays empty.
  - Putting the token in a drop-in Environment=: EnvironmentFile wins,
    and anyone can read Environment= with systemctl show.
  - Only testing with curl: proves the token, fixes nothing.
  - Touching the hub: it is the vendor's device; fix the client.

DO IT BETTER
  - 401 vs 403 vs 404 first, THEN guess. Read the body: APIs say why.
  - curl -i shows the status line; curl -v shows every step (the TLS
    handshake too): look for the line starting `< HTTP/1.1`.
  - Use --cacert /etc/hub-sync/hub.crt instead of -k when it's there.
  - Someone watching your screen? Keep the token off it: in bash,
    T=$(sudo cat /etc/hub-sync/token.new) stores the file's contents in
    $T without printing them; then use "Authorization: Bearer $T".
  - Tell the hub team: rotations must be pushed to the NVR, or the
    dashboard goes blank at every maintenance window.
