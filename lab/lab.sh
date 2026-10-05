# network lab for LAB=1 scenarios (sourced by drill.sh)
#   drill-lan 10.50.0.0/24  box .50   gateway/DNS .254 (drill-gw)
#   drill-cam 10.50.1.0/24  camera1 .31 (drill-cam)         gw is dual-homed and forwards
# Plain bridge networks with masquerade OFF: no NAT to the outside. (--internal networks would be tidier,
# but Docker's bridge-netfilter DROPs frames routed through the gateway container on them.)
LAB_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
LAB_ARGS=()

lab_owner() { docker inspect -f '{{index .Config.Labels "drills.owner"}}' drill-gw 2>/dev/null; }

lab_down_all() {
  docker rm -f drill-gw drill-cam >/dev/null 2>&1
  docker network rm drill-lan drill-cam >/dev/null 2>&1
  return 0
}

lab_down_owner() {   # tear the lab down only if this drill created it
  local o; o=$(lab_owner) || return 0
  [ "$o" = "$1" ] && lab_down_all
  return 0
}

lab_up() {   # lab_up <owner-ns> [up|down]   (second arg: state of the camera)
  local owner=$1 cam=${2:-up} o
  if docker inspect drill-gw >/dev/null 2>&1; then
    o=$(lab_owner)
    [ "$o" = "$owner" ] || { echo "the network lab is in use by drill '$o' (./drill.sh clean, or finish that drill)" >&2; return 1; }
    lab_down_all
  fi
  docker network rm drill-lan drill-cam >/dev/null 2>&1
  docker network create --opt com.docker.network.bridge.enable_ip_masquerade=false --subnet 10.50.0.0/24 drill-lan >/dev/null || return 1
  docker network create --opt com.docker.network.bridge.enable_ip_masquerade=false --subnet 10.50.1.0/24 drill-cam >/dev/null || return 1
  local img=${IMAGE:-linux-drills:base}
  docker run -d --name drill-gw --hostname gw --label drills=1 --label "drills.owner=$owner" \
    --network drill-lan --ip 10.50.0.254 --cap-add NET_ADMIN --sysctl net.ipv4.ip_forward=1 \
    --entrypoint /bin/bash "$img" -c \
    'dnsmasq -k --no-resolv --no-hosts --listen-address=10.50.0.254 --bind-interfaces --address=/camera1.facility.lan/10.50.1.31 & exec sleep infinity' >/dev/null || return 1
  docker network connect --ip 10.50.1.254 drill-cam drill-gw || return 1
  if [ "$cam" != down ]; then
    docker run -d --name drill-cam --hostname camera1 --label drills=1 --label "drills.owner=$owner" \
      --network drill-cam --ip 10.50.1.31 --cap-add NET_ADMIN -v "$LAB_DIR/camera.py:/camera.py:ro" \
      --entrypoint /bin/bash "$img" -c 'ip route add 10.50.0.0/24 via 10.50.1.254; exec python3 /camera.py' >/dev/null || return 1
  fi
  local i
  for i in $(seq 1 40); do
    docker exec drill-gw ss -lun 2>/dev/null | grep -q '10.50.0.254:53' \
      && { [ "$cam" = down ] || docker exec drill-cam ss -ltn 2>/dev/null | grep -q ':80 '; } && break
    sleep 0.25
  done
  LAB_ARGS=(--network drill-lan --ip 10.50.0.50 --dns 10.50.0.254 -v "$LAB_DIR:/drill-lab:ro")
}
