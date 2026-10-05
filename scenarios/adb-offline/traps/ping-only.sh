# "network problem": ping and port-probe the hub, never touch adb
ping -c2 -W1 10.50.0.77 || true
nc -zv -w2 10.50.0.77 5555 || true
