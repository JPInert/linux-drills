# a hand-run port forwarder 9091 -> 9090: works until the next reboot
cat > /root/fwd.py <<'PY'
import socket, threading
s = socket.socket(); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(("127.0.0.1", 9091)); s.listen(16)
def pipe(a, b):
    try:
        while True:
            d = a.recv(65536)
            if not d: break
            b.sendall(d)
    except OSError: pass
    finally: a.close(); b.close()
while True:
    c, _ = s.accept(); u = socket.create_connection(("127.0.0.1", 9090))
    threading.Thread(target=pipe, args=(c, u), daemon=True).start()
    threading.Thread(target=pipe, args=(u, c), daemon=True).start()
PY
setsid python3 /root/fwd.py >/dev/null 2>&1 < /dev/null &
sleep 12
