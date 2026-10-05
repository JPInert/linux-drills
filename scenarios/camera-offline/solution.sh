set -e
ip a; ip r
ping -c2 10.50.0.254
ping -c2 10.50.1.31 || true
answer "The box is healthy (right IP, route and gateway; gateway 10.50.0.254 answers). The gateway reports host unreachable for camera1 10.50.1.31, so the camera or its switch port is down or unpowered. Do not reboot the NVR: escalate to an on-site tech to check camera power, PoE and cable."
