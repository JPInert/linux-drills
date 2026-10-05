#!/usr/bin/env bash
# drill.sh - Linux break-fix drills in Docker.  ./drill.sh help
set -uo pipefail

HERE=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
NS=${DRILL_NS:-drill}                       # container name; one live drill per name
IMAGE=${DRILL_IMAGE:-linux-drills:base}
DATA=${DRILL_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/linux-drills}
LOG=$DATA/drills.tsv
SCEN=$HERE/scenarios
LABLIB=$HERE/lab/lab.sh

c_b=$'\033[1m'; c_g=$'\033[32m'; c_r=$'\033[31m'; c_y=$'\033[33m'; c_d=$'\033[2m'; c_0=$'\033[0m'
[ -t 1 ] || { c_b=; c_g=; c_r=; c_y=; c_d=; c_0=; }
die() { echo "${c_r}error:${c_0} $*" >&2; exit 1; }
say() { echo "${c_d}$*${c_0}"; }
fmt() { local s=${1:-0}; [ "$s" -gt 0 ] 2>/dev/null && printf '%d:%02d' $((s / 60)) $((s % 60)) || printf -- '-'; }

need_docker() {
  command -v docker >/dev/null || die "docker not found"
  docker info >/dev/null 2>&1 || die "cannot talk to the docker daemon (is it running? are you in the docker group?)"
  [ "$(stat -fc %T /sys/fs/cgroup 2>/dev/null)" = cgroup2fs ] || [ -n "${DRILL_PRIVILEGED:-}" ] \
    || die "needs cgroup v2 for systemd-in-Docker. On cgroup v1 hosts: DRILL_PRIVILEGED=1 ./drill.sh ..."
}

scenarios() { find "$SCEN" -mindepth 2 -maxdepth 2 -name meta.env -printf '%h\n' | xargs -rn1 basename | sort; }
meta() { ( . "$SCEN/$1/meta.env"; eval "printf '%s' \"\${$2:-}\"" ); }   # meta <scenario> <VAR>
have() { [ -f "$SCEN/$1/meta.env" ]; }

# areas: groups of tags, so `random --area network` and `menu` pick up new scenarios by their TAGS alone
AREAS=(network gpu docker systemd disk cpu-mem logs chain)
area_tags() { case $1 in
  network) echo "network dns ssh rtsp camera ip-route ip-addr firewall iptables dhcp vlan routing wifi poe oob proxy" ;;
  gpu)     echo "gpu nvidia-smi cuda vram" ;;
  docker)  echo "docker compose" ;;
  systemd) echo "systemd enable mask journalctl" ;;
  disk)    echo "disk inodes df du" ;;
  cpu-mem) echo "cpu memory top" ;;
  logs)    echo "logs grep awk config" ;;
  chain)   echo "chain" ;;
  *)       return 1 ;;
esac; }
in_area() {  # in_area <scenario> <area>
  local t; for t in $(meta "$1" TAGS); do case " $(area_tags "$2") " in *" $t "*) return 0 ;; esac; done; return 1
}

# XP: level x 100 for a clean solve, -25 per hint, 10 for a peek; streak = SOLVED rows in a row, newest back
xp_row() {  # xp_row <scenario> <result> <hints>
  local lvl; lvl=$(meta "$1" LEVEL 2>/dev/null); lvl=${lvl:-1}
  case $2 in SOLVED) local x=$(( lvl * 100 - ${3:-0} * 25 )); [ $x -lt 25 ] && x=25; echo $x ;; PEEKED) echo 10 ;; *) echo 0 ;; esac
}
xp_total() { local t=0 w n r h x; [ -s "$LOG" ] || { echo 0; return; }
  while IFS=$'\t' read -r w n r _ _ h _; do x=$(xp_row "$n" "$r" "$h"); t=$((t + x)); done < "$LOG"; echo $t; }
streak() { [ -s "$LOG" ] || { echo 0; return; }; tac "$LOG" | awk -F'\t' '$3!="SOLVED"{exit} {n++} END{print n+0}'; }
rank() {  # rank <xp>
  local x=$1
  if   [ "$x" -lt 300 ];  then echo "Trainee|300"
  elif [ "$x" -lt 1000 ]; then echo "Tier 1 Responder|1000"
  elif [ "$x" -lt 2500 ]; then echo "Tier 2 Troubleshooter|2500"
  elif [ "$x" -lt 5000 ]; then echo "Field Ops Engineer|5000"
  else                         echo "On-call Legend|"; fi
}
xp_bar() {  # xp_bar <xp>: rank, progress bar to the next rank
  local x=$1 r nxt w=24 fill; IFS='|' read -r r nxt <<< "$(rank "$x")"
  if [ -z "$nxt" ]; then printf '%s%s%s  %d XP  (max rank)\n' "$c_b" "$r" "$c_0" "$x"; return; fi
  fill=$(( x * w / nxt )); [ $fill -gt $w ] && fill=$w
  printf '%s%-22s%s [%s%s%s%s] %d / %d XP to next rank\n' "$c_b" "$r" "$c_0" "$c_g" "$(printf '%*s' $fill '' | tr ' ' '#')" "$c_0" "$(printf '%*s' $((w - fill)) '' | tr ' ' '.')" "$x" "$nxt"
}

# ---------------------------------------------------------------- image
image_hash() { (cd "$HERE/image" && find . -type f -print0 | sort -z | xargs -0 sha1sum | sha1sum | cut -c1-12); }
ensure_image() {
  local want have; want=$(image_hash)
  have=$(docker image inspect -f '{{index .Config.Labels "drills.hash"}}' "$IMAGE" 2>/dev/null || true)
  [ "$have" = "$want" ] && return 0
  say "building $IMAGE ($([ -z "$have" ] && echo first build || echo image changed))..."
  docker build -q --label "drills.hash=$want" -t "$IMAGE" "$HERE/image" >/dev/null || die "image build failed (run: docker build $HERE/image)"
}

# ---------------------------------------------------------------- container lifecycle
cexists()  { docker inspect "$NS" >/dev/null 2>&1; }
crunning() { [ "$(docker inspect -f '{{.State.Running}}' "$NS" 2>/dev/null)" = true ]; }
cx()       { docker exec -u root "$NS" "$@"; }

teardown() {
  docker rm -f "$NS" "$NS-lab" >/dev/null 2>&1 || true
  [ -f "$LABLIB" ] && { . "$LABLIB"; lab_down_owner "$NS"; } 2>/dev/null
  return 0
}

boot() {  # boot <scenario> [flags...]: start container, wait for systemd, apply the break
  local name=$1; shift
  local lab; lab=$(meta "$name" LAB)
  local -a extra=()
  local dargs; dargs=$(meta "$name" DOCKER_ARGS)
  local host; host=$(meta "$name" BOXNAME); host=${host:-edge-nvr-03}
  # shellcheck disable=SC2206
  extra=($dargs)
  cexists && docker rm -f "$NS" >/dev/null
  docker rm -f "$NS-lab" >/dev/null 2>&1
  if [ "${lab:-0}" = 1 ]; then
    [ -f "$LABLIB" ] || die "scenario needs the network lab but $LABLIB is missing"
    . "$LABLIB"; lab_up "$NS" "$(meta "$name" LAB_CAM)" || return 1
    extra+=("${LAB_ARGS[@]}")
  fi
  [ "${SSH_MODE:-0}" = 1 ] && extra+=(-p "127.0.0.1:$SSH_PORT:22")
  local -a priv=(--cgroupns=host -v /sys/fs/cgroup:/sys/fs/cgroup:rw)
  [ -n "${DRILL_PRIVILEGED:-}" ] && priv=(--privileged --cgroupns=host)
  docker run -d --name "$NS" --hostname "$host" --label drills=1 \
    "${priv[@]}" --tmpfs /run --tmpfs /run/lock --tmpfs /tmp \
    --cap-add NET_ADMIN --cap-add SYS_PTRACE --cpus 1 --memory 512m --pids-limit 1024 \
    "$@" "${extra[@]}" -v "$SCEN/$name:/drill:ro" "$IMAGE" >/dev/null || return 1
  timeout 90 docker exec "$NS" systemctl is-system-running --wait >/dev/null 2>&1 || true
  crunning || { docker logs "$NS" 2>&1 | tail -5; return 1; }
  local i st   # be sure systemd + dbus are really up before the break runs
  for i in $(seq 1 60); do
    st=$(docker exec "$NS" systemctl is-system-running 2>/dev/null)
    case $st in running|degraded) docker exec "$NS" busctl --system status >/dev/null 2>&1 && break ;; esac
    sleep 0.5
  done
  SIDE_ENV=()
  if [ -f "$SCEN/$name/lab-box.sh" ]; then
    side_up "$name" || { echo "${c_r}scenario '$name': its lab stand-in failed to start (a bug in the scenario, not you)${c_0}" >&2; return 1; }
  fi
  if ! out=$(docker exec -u root "${SIDE_ENV[@]}" "$NS" bash -c 'set -e; cd /drill; export DRILL_LAB=${DRILL_LAB:-0}; . /drill/break.sh' 2>&1); then
    echo "$out" | tail -15; echo "${c_r}scenario '$name' break.sh failed (a bug in the scenario, not you)${c_0}" >&2; return 1
  fi
  if [ "${SSH_MODE:-0}" = 1 ]; then
    docker exec -i -u root "$NS" bash -c 'install -d -m700 -o tech -g tech /home/tech/.ssh; cat > /home/tech/.ssh/authorized_keys; chown tech:tech /home/tech/.ssh/authorized_keys; chmod 600 /home/tech/.ssh/authorized_keys' < "$SSH_KEY.pub"
  fi
  custom_prompt
  cx bash -c "echo '$name' > /var/lib/drill/scenario; : > /var/lib/drill/checks; rm -f /var/lib/drill/{solved,hints,peeked,answer}; : > /var/lib/drill/typos; : > /var/lib/drill/cmdlog; chmod 666 /var/lib/drill/cmdlog; rm -f /var/lib/drill/hintlog; date +%s > /var/lib/drill/start"
}

custom_prompt() {  # optional: your own prompt inside the box, drill clock in front of it
  # Opt-in: set DRILL_PROMPT_DIR to a dir holding statusline.bash + remote-prompt.bash (your own prompt files).
  # Unset, DRILL_PLAIN=1 or no files = the stock box prompt, like a remote assessment box. The guard stops the
  # loop remote-prompt.bash would start if it sources ~/.bashrc, which sources this file again.
  local d=${DRILL_PROMPT_DIR:-}
  [ -n "$d" ] && [ -z "${DRILL_PLAIN:-}" ] && [ -r "$d/statusline.bash" ] && [ -r "$d/remote-prompt.bash" ] || return 0
  { printf '[ -n "${_drill_prompt:-}" ] && return 0; _drill_prompt=1\n'
    cat "$d/statusline.bash" "$d/remote-prompt.bash"
    printf '%s\n' "PS1='\[\e[33m\][\$(_drill_elapsed)]\[\e[0m\] '\"\$PS1\""
    # a stray Ctrl-D must not end the drill: bash says 'Use "exit" to leave the shell.' (10 in a row still exit)
    printf 'set -o ignoreeof\n'
    # the box has no git: the status line's `git status` must not land in the typo log every prompt
    printf '%s\n' 'eval "__sl_build_real() $(declare -f __sl_build | tail -n +2)"' \
      '__sl_build() { local _drill_sl=1; __sl_build_real "$@"; }' \
      'eval "__drill_cnf() $(declare -f command_not_found_handle | tail -n +2)"' \
      'command_not_found_handle() { [ -n "${_drill_sl:-}" ] && return 127; __drill_cnf "$@"; }'
  } | docker exec -i -u root "$NS" bash -c 'cat > /var/lib/drill/prompt.bash; chmod 644 /var/lib/drill/prompt.bash
      for h in /home/tech /root; do echo "[ -r /var/lib/drill/prompt.bash ] && . /var/lib/drill/prompt.bash" >> $h/.bashrc; done'
}

side_up() {  # side_up <scenario>: the far end (NOC host, hubs, cameras) in its OWN container + network namespace
  # so none of it shows on the box: not in ps, ss, systemctl or /etc. lab-box.sh runs in the box, makes the
  # veth pair and prints KEY=VAL lines; each LINK=<peer> is moved into the sidecar's namespace (a privileged
  # nsenter helper: the box itself cannot see the sidecar); lab-side.sh runs in the sidecar with those as env,
  # brings its end up, starts the stand-in, and may print KEY=VAL lines that break.sh gets as env.
  local name=$1 side=$NS-lab env out l bp sp
  docker run -d --init --name "$side" --hostname lab --label drills=1 --label "drills.owner=$NS" --network none \
    --cap-add NET_ADMIN --cap-add NET_RAW -v "$SCEN/$name:/drill:ro" --entrypoint sleep "$IMAGE" infinity >/dev/null || return 1
  env=$(cx bash -c 'set -e; cd /drill; . /drill/lab-box.sh' 2>&1) || { echo "$env" | tail -10; return 1; }
  bp=$(docker inspect -f '{{.State.Pid}}' "$NS"); sp=$(docker inspect -f '{{.State.Pid}}' "$side")
  for l in $(printf '%s\n' "$env" | sed -n 's/^LINK=//p'); do
    docker run --rm --privileged --pid=host --network none --entrypoint nsenter "$IMAGE" -t "$bp" -n ip link set "$l" netns "$sp" || return 1
  done
  local -a e=(); while IFS= read -r l; do [[ $l =~ ^[A-Z_][A-Z0-9_]*= ]] && e+=(-e "$l"); done <<< "$env"
  out=$(docker exec "${e[@]}" "$side" bash -c 'set -e; cd /drill; . /drill/lab-side.sh' 2>&1) || { echo "$out" | tail -10; return 1; }
  while IFS= read -r l; do [[ $l =~ ^[A-Z_][A-Z0-9_]*= ]] && SIDE_ENV+=(-e "$l"); done <<< "$out"
  return 0
}

# ---------------------------------------------------------------- results
report() { cx /usr/local/lib/drill/drill-report 2>/dev/null; }   # key=value lines

record() {  # record <scenario>: read the container's state, append to the log
  local name=$1 scenario='' start=0 solved=0 hints=0 peeked=0 checks=0 typos=0 now result solve_s
  eval "$(report)" 2>/dev/null || return 0
  now=$(date +%s)
  if [ "${solved:-0}" -gt 0 ]; then result=SOLVED; [ "$peeked" = 1 ] && result=PEEKED; solve_s=$((solved - start))
  else result=UNSOLVED; [ "$peeked" = 1 ] && result=PEEKED; solve_s=0; fi
  mkdir -p "$DATA"
  printf '%s\t%s\t%s\t%d\t%d\t%s\t%s\t%s\n' "$(date '+%F %H:%M')" "$name" "$result" "$solve_s" "$((now - start))" "$hints" "$checks" "$typos" >> "$LOG"
  echo
  case $result in
    SOLVED)   echo "${c_g}SOLVED${c_0} $name in $(fmt $solve_s)  hints:$hints  checks:$checks  typos:$typos" ;;
    PEEKED)   echo "${c_y}PEEKED${c_0} $name  (looked at the solution; ran $(fmt $((now - start))))  hints:$hints" ;;
    *)        echo "${c_r}UNSOLVED${c_0} $name after $(fmt $((now - start)))  hints:$hints  -> 'solution' next time, then redo it" ;;
  esac
  local gained total st; gained=$(xp_row "$name" "$result" "$hints"); total=$(xp_total); st=$(streak)
  echo "  +$gained XP$([ "$st" -gt 1 ] && echo "   streak: $st solved in a row")"
  echo "  $(xp_bar "$total")"
  echo "logged to $LOG   (./drill.sh log)"
  local deb; deb=$(cx bash -c 'drill-debrief' 2>/dev/null)
  [ -n "$deb" ] && printf '%s\n' "$deb"
  runlog "$name" "$result" "${start:-0}" "$now" "$solve_s" "$hints" "$checks" "$deb"
}

runlog() {  # runlog <scenario> <result> <start> <now> <solve_s> <hints> <checks> <debrief>: the path you took -> $DATA/runs/
  local name=$1 result=$2 start=$3 now=$4 solve_s=$5 hints=$6 checks=$7 deb=$8 tmp f x peek
  [ "$start" -gt 0 ] 2>/dev/null || return 0
  tmp=$(mktemp -d); mkdir -p "$DATA/runs"
  f=$DATA/runs/$(date -d "@$start" '+%F-%H%M')-$name.log
  for x in cmdlog checks hintlog; do cx cat "/var/lib/drill/$x" > "$tmp/$x" 2>/dev/null; done
  cx cat /home/tech/.bash_history > "$tmp/hist.tech" 2>/dev/null; cx cat /root/.bash_history > "$tmp/hist.root" 2>/dev/null
  peek=$(cx stat -c %Y /var/lib/drill/peeked 2>/dev/null)
  {
    if [ -s "$tmp/cmdlog" ]; then sed 's/^/C\t/' "$tmp/cmdlog"
    else   # a box from an older image: no cmdlog, so history (times, no exit status)
      awk '/^#[0-9]+$/{t=substr($0,2); next} t!=""{print "C\t" t "\t?\t" $0}' "$tmp"/hist.*
    fi
    awk '{print "K\t" $1 "\t" $2}' "$tmp/checks"; awk '{print "H\t" $1 "\t" $2}' "$tmp/hintlog"
    [ -n "$peek" ] && printf 'P\t%s\n' "$peek"
    # optional: questions an external coach logged while this box was up ($DATA/coach.log: epoch, box, Q|A, text)
    [ -f "$DATA/coach.log" ] && awk -F'\t' -v a="$start" -v b="$now" -v ns="$NS" '$2==ns && $1>=a && $1<=b {print "A\t" $1 "\t" $3 "\t" $4}' "$DATA/coach.log"
  } 2>/dev/null | sort -t$'\t' -k2,2n -s > "$tmp/all"
  # active time: gaps over 5 min between steps count as away, not working
  local active; active=$(awk -F'\t' -v s="$start" -v e="${solve_s:-0}" '{d=$2-p; if(NR==1)d=$2-s; if(d>0&&d<=300)w+=d; p=$2} END{printf "%d", w}' "$tmp/all")
  {
    printf '# %s  %s' "$name" "$result"
    [ "${solve_s:-0}" -gt 0 ] && printf ' in %s' "$(fmt "$solve_s")"
    printf '  (active about %d min)  hints %s  checks %s  started %s\n' $(( (active + 59) / 60 )) "$hints" "$checks" "$(date -d "@$start" '+%F %H:%M')"
    printf '# m:ss = since the drill started; rc = exit status when it was not 0 (127 = typo / not found)\n\n'
    awk -F'\t' -v s="$start" '
      function t(x,  d){ d=x-s; if(d<0)d=0; return sprintf("%3d:%02d", int(d/60), d%60) }
      { g=$2-p; if(NR==1)g=$2-s; if(g>300) printf "          ... %d min away\n", int(g/60); p=$2 }
      $1=="C" && $4 ~ /^(check|hint)( |$)/ { next }          # their K / H lines say more
      $1=="C" { rc=($3=="0"||$3=="?")?"":"rc=" $3; printf "%s  %-6s %s\n", t($2), rc, $4; next }
      $1=="K" { printf "%s  %-6s check: %s\n", t($2), "", $3; next }
      $1=="H" { printf "%s  %-6s hint %s\n", t($2), "", $3; next }
      $1=="P" { printf "%s  %-6s solution (peeked)\n", t($2), ""; next }
      $1=="A" { printf "%s  %-6s coach %s: %s\n", t($2), "", ($3=="Q"?"asked":"got"), $4; next }' "$tmp/all"
    [ -n "$deb" ] && { echo; printf '%s\n' "$deb" | sed 's/\x1b\[[0-9;]*[A-Za-z]//g'; }
  } > "$f"
  rm -rf "$tmp"
  echo "path logged to $f   (./drill.sh review)"
}

# Keys pressed while nothing reads them (spin-up, the ssh probe, the report) echo as ^[[D^[[D... and then
# land in the box's first prompt. Mute echo while busy; drop whatever queued up just before a reader starts.
kb_mute()  { [ -t 0 ] && stty -echo 2>/dev/null; return 0; }
kb_flush() { [ -t 0 ] || return 0; local _k; while read -r -s -t 0.05 -n 256 _k; do :; done; stty echo 2>/dev/null; return 0; }

enter() {  # enter <scenario> [--root]: attach a shell, then record + tear down
  local name=$1 user=tech home=/home/tech keep=${KEEP:-0}
  [ "${2:-}" = --root ] && { user=root; home=/root; }
  local sshopt=() ssh_ok=0 i
  if [ "${SSH_MODE:-0}" = 1 ] && [ "$user" = tech ] && ! meta "$name" TAGS | tr ' ' '\n' | grep -qx ssh; then
    sshopt=(-i "$SSH_KEY" -p "$SSH_PORT" -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR)
    # the break may take the box's own address away (wrong-ip flushes eth0, so docker's 127.0.0.1:port
    # forward dead-ends: "kex_exchange_identification: Connection reset"), or sshd is slow on a small host
    for i in 1 2 3 4 5 6 7 8 9 10; do
      ssh "${sshopt[@]}" -o ConnectTimeout=3 -o BatchMode=yes tech@127.0.0.1 true 2>/dev/null && { ssh_ok=1; break; }
      sleep 1
    done
    [ "$ssh_ok" = 1 ] || say "(this break cut the box off the network: using the console instead of ssh)"
  fi
  kb_flush
  if [ "$ssh_ok" = 1 ]; then
    say "ssh -p $SSH_PORT tech@127.0.0.1   (key: $SSH_KEY)"
    ssh -tt "${sshopt[@]}" tech@127.0.0.1
  else
    [ "${SSH_MODE:-0}" = 1 ] && [ "$user" = tech ] && meta "$name" TAGS | tr ' ' '\n' | grep -qx ssh \
      && say "(this scenario is about sshd itself: using the console instead of ssh)"
    docker exec -it -u "$user" -w "$home" "$NS" bash -l
  fi
  NEXT_REQ=0; cx test -f /var/lib/drill/next 2>/dev/null && NEXT_REQ=1
  record "$name"
  if [ "$keep" = 1 ]; then say "kept container '$NS' (./drill.sh attach | ./drill.sh clean)"; else teardown; fi
}

# ---------------------------------------------------------------- commands
ssh_setup() {  # --ssh: enter over real ssh (127.0.0.1:$SSH_PORT) with a throwaway key, like a remote assessment
  command -v ssh >/dev/null && command -v ssh-keygen >/dev/null || die "--ssh needs ssh and ssh-keygen on the host"
  SSH_MODE=1; SSH_PORT=${DRILL_SSH_PORT:-2222}; SSH_KEY=$DATA/id_drill
  mkdir -p "$DATA"; [ -f "$SSH_KEY" ] || ssh-keygen -q -t ed25519 -N '' -C linux-drills -f "$SSH_KEY"
  # busy because our own drill box still maps it (a closed terminal left it up): cmd_run offers to log it
  if ss -ltn 2>/dev/null | grep -q ":$SSH_PORT " && ! docker port "$NS" 22/tcp 2>/dev/null | grep -q ":$SSH_PORT\$"; then
    die "host port $SSH_PORT is busy (DRILL_SSH_PORT=... to change it)"
  fi
  return 0
}

cmd_run() {
  need_docker; ensure_image
  local name=${1:-}; shift || true
  [ -n "$name" ] || die "usage: run <scenario>   (./drill.sh list)"
  have "$name" || die "no scenario '$name' (./drill.sh list)"
  local root='' chain=()
  for a in "$@"; do case $a in --root) root=--root; chain+=(--root) ;; --keep) KEEP=1 ;; --ssh) ssh_setup; chain+=(--ssh) ;; *) die "unknown flag $a" ;; esac; done
  if crunning; then
    local old a; old=$(cx cat /var/lib/drill/scenario 2>/dev/null)
    say "a drill ('$old') is still up in container '$NS' (open in another terminal, or its terminal was closed)."
    read -r -p "[Enter] log it and start a new one   [a] go back into it   [q] quit: " a
    case $a in
      a*|A*) cmd_attach; return ;;
      q*|Q*) exit 0 ;;
      *)     record "${old:-?}"; teardown ;;
    esac
  fi
  trap 'stty echo 2>/dev/null; teardown; exit 130' INT TERM
  # closing the terminal tab (SIGHUP) used to orphan the box: it kept :2222 and the run was never logged
  trap 'record "$name" >/dev/null 2>&1; teardown; exit 129' HUP
  say "spinning up '$name' (breaking a fresh box; ~10s)..."
  kb_mute
  boot "$name" || { stty echo 2>/dev/null; teardown; die "could not start '$name'"; }
  enter "$name" $root
  # one drill done: offer the next one (a session asks on its own). `next` inside the box skips the question.
  [ -n "${IN_SESSION:-}" ] && return 0
  if [ "${NEXT_REQ:-0}" != 1 ]; then
    # -e: readline, so arrow keys move the cursor instead of printing ^[[D; q / quit / exit all stop
    kb_flush; local a; read -e -r -p "next drill? [Enter = next, q = quit] " a; case ${a,,} in q*|exit|x) return 0 ;; esac
  fi
  # same filters as the random pick that led here, else the same level as the drill just finished
  local -a f; read -r -a f <<< "${DRILL_CHAIN:---level $(meta "$name" LEVEL)}"
  exec "$HERE/drill.sh" random "${f[@]}" "${chain[@]}"
}

cmd_attach() {
  need_docker; crunning || die "no running drill in '$NS'"
  local name; name=$(cx cat /var/lib/drill/scenario 2>/dev/null); enter "${name:-?}" "$@"
}

cmd_random() {
  need_docker
  local level='' tag='' area='' nolab=0 pass=()
  while [ $# -gt 0 ]; do case $1 in
    --level) level=$2; shift ;; --tag) tag=$2; shift ;; --area) area=$2; shift ;; --no-lab) nolab=1 ;; --ssh|--root) pass+=("$1") ;; *) die "unknown flag $1" ;;
  esac; shift; done
  [ -z "$area" ] || area_tags "$area" >/dev/null || die "no area '$area' (areas: ${AREAS[*]})"
  local pool=() s
  for s in $(scenarios); do
    [ -n "$level" ] && [ "$(meta "$s" LEVEL)" != "$level" ] && continue
    [ -n "$tag" ] && ! meta "$s" TAGS | tr ' ' '\n' | grep -qx "$tag" && continue
    [ -n "$area" ] && ! in_area "$s" "$area" && continue
    [ "$nolab" = 1 ] && [ "$(meta "$s" LAB)" = 1 ] && continue
    [ -z "$tag" ] && [ "$(meta "$s" PARKED)" = 1 ] && continue   # parked: only by name or --tag
    pool+=("$s")
  done
  [ ${#pool[@]} -gt 0 ] || die "no scenario matches"
  # least recently done first (never-done = oldest); random among ties
  local pick
  pick=$(for s in "${pool[@]}"; do
      last=$(awk -F'\t' -v s="$s" '$2==s{l=$1} END{print l?l:"0000"}' "$LOG" 2>/dev/null || echo 0000)
      printf '%s\t%s\t%s\n' "$last" "$RANDOM" "$s"
    done | sort | head -1 | cut -f3)
  [ -n "$pick" ] || pick=${pool[RANDOM % ${#pool[@]}]}
  local keep=(); [ -n "$level" ] && keep+=(--level "$level"); [ -n "$tag" ] && keep+=(--tag "$tag"); [ -n "$area" ] && keep+=(--area "$area"); [ "$nolab" = 1 ] && keep+=(--no-lab)
  export DRILL_CHAIN="${keep[*]}"
  say "random scenario (name hidden until you finish)"
  cmd_run "$pick" "${pass[@]}"
}

cmd_session() {  # session [N] [random-filters]: back-to-back random drills
  local n=5; [[ ${1:-} =~ ^[0-9]+$ ]] && { n=$1; shift; }
  local i a
  for i in $(seq 1 "$n"); do
    echo "${c_b}== drill $i of $n ==${c_0}"
    ( IN_SESSION=1 cmd_random "$@" )
    [ "$i" -lt "$n" ] && { read -e -r -p "next drill? [Enter = go, q = stop] " a; case ${a,,} in q*|exit|x) break ;; esac; }
  done
  cmd_log
}

cmd_menu() {  # menu [--ssh]: pick an area (or anything), then a random least-recently-done drill from it
  local a i=1 n s solved total
  total=$(xp_total)
  echo
  echo "${c_b}  LINUX DRILLS  ${c_0}${c_d}edge-nvr-03 / Northgate Garage${c_0}"
  echo "  $(xp_bar "$total")"
  [ "$(streak)" -gt 1 ] && echo "  streak: $(streak) solved in a row"
  echo
  printf '  %s%-3s %-10s %6s %7s%s\n' "$c_d" '#' AREA DRILLS SOLVED "$c_0"
  printf '  %-3s %-10s %6s %7s\n' 0 anything "$(scenarios | while read -r s; do [ "$(meta "$s" PARKED)" = 1 ] || echo; done | wc -l)" ''
  for a in "${AREAS[@]}"; do
    n=0; solved=0
    for s in $(scenarios); do
      [ "$(meta "$s" PARKED)" = 1 ] && continue; in_area "$s" "$a" || continue; n=$((n + 1))
      awk -F'\t' -v s="$s" '$2==s && $3=="SOLVED"{f=1} END{exit !f}' "$LOG" 2>/dev/null && solved=$((solved + 1))
    done
    printf '  %-3s %-10s %6s %7s\n' "$i" "$a" "$n" "$solved/$n"; i=$((i + 1))
  done
  echo
  local pick lvl=''; read -r -p "  area # [Enter = anything]: " pick
  read -r -p "  level 1-3 [Enter = any]: " lvl
  local -a f=(); [[ $lvl =~ ^[1-3]$ ]] && f+=(--level "$lvl")
  if [[ $pick =~ ^[0-9]+$ ]] && [ "$pick" -ge 1 ] && [ "$pick" -le ${#AREAS[@]} ]; then f+=(--area "${AREAS[pick-1]}"); fi
  cmd_random "${f[@]}" "$@"
}

cmd_list() {
  local verbose=0; [ "${1:-}" = -v ] && verbose=1
  printf '%s%-22s %-3s %-6s %-6s %s%s\n' "$c_b" SCENARIO LVL DONE BEST "$([ $verbose = 1 ] && echo 'TAGS / TITLE (spoilers)')" "$c_0"
  local s
  for s in $(scenarios); do
    local done best
    read -r done best < <(awk -F'\t' -v s="$s" '$2==s && $3=="SOLVED"{n++; if(!b||$4<b)b=$4} END{print n+0, b+0}' "$LOG" 2>/dev/null || echo "0 0")
    printf '%-22s %-3s %-6s %-6s %s%s\n' "$s" "$(meta "$s" LEVEL)" "${done:-0}" "$(fmt "${best:-0}")" \
      "$([ $verbose = 1 ] && echo "$(meta "$s" TAGS) | $(meta "$s" TITLE)")" "$([ "$(meta "$s" LAB)" = 1 ] && echo ' [lab]')$([ "$(meta "$s" PARKED)" = 1 ] && echo ' [parked]')"
  done
}

cmd_review() {  # review [N|NAME|list]: the path log of the last drill (N = Nth from last, NAME = latest of it)
  local d=$DATA/runs f
  ls "$d"/*.log >/dev/null 2>&1 || { echo "no run logs yet ($d)"; return 0; }
  case ${1:-} in
    '')     f=$(ls "$d"/*.log | tail -1) ;;
    list)   ls -1 "$d" | tail -30; return 0 ;;
    [0-9]*) f=$(ls "$d"/*.log | tail -n "$1" | head -1) ;;
    *)      f=$(ls "$d"/*"$1"*.log 2>/dev/null | tail -1) ;;
  esac
  [ -n "$f" ] || die "no run log matches '$1' (./drill.sh review list)"
  cat "$f"; say "($f)"
}

cmd_log() {
  [ -s "$LOG" ] || { echo "no drills logged yet ($LOG)"; return 0; }
  echo "${c_b}PER SCENARIO${c_0}"
  awk -F'\t' 'BEGIN{printf "%-22s %5s %6s %8s %8s %6s %s\n","SCENARIO","RUNS","SOLVED","BEST","LAST","HINTS","LAST RUN"}
    {r[$2]++; if($3=="SOLVED"){s[$2]++; if(!b[$2]||$4<b[$2])b[$2]=$4; l[$2]=$4} h[$2]+=$6; d[$2]=$1; st[$2]=$3}
    function f(x){return x>0?sprintf("%d:%02d",x/60,x%60):"-"}
    END{for(k in r) printf "%-22s %5d %6d %8s %8s %6.1f %s %s\n",k,r[k],s[k],f(b[k]),f(l[k]),h[k]/r[k],d[k],st[k]}' "$LOG" | { read -r h; echo "$h"; sort; }
  echo; echo "${c_b}RECENT${c_0}"
  printf '%-17s %-22s %-9s %7s %7s %5s\n' WHEN SCENARIO RESULT SOLVE TOTAL HINTS
  tail -12 "$LOG" | awk -F'\t' 'function f(x){return x>0?sprintf("%d:%02d",x/60,x%60):"-"} {printf "%-17s %-22s %-9s %7s %7s %5s\n",$1,$2,$3,f($4),f($5),$6}'
  echo; awk -F'\t' '$3=="SOLVED"{n++; t+=$4} END{printf "%d solved, mean %s\n", n, n?sprintf("%d:%02d",t/n/60,(t/n)%60):"-"}' "$LOG"
  xp_bar "$(xp_total)"; [ "$(streak)" -gt 1 ] && echo "streak: $(streak) solved in a row"
}

cmd_clean() { need_docker; teardown; [ -f "$LABLIB" ] && { . "$LABLIB"; lab_down_all; }; docker ps -aq --filter label=drills=1 | xargs -r docker rm -f >/dev/null; say "clean"; }

# ---------------------------------------------------------------- selftest: broken -> check FAILS; solution.sh -> check PASSES
selftest_one() {  # selftest_one <scenario>  (own container name so runs can be parallel)
  local name=$1 out rc=0 errs=()
  export DRILL_NS="drillst-${ST_RUN:-x}-$name"; NS=$DRILL_NS   # ST_RUN: parallel selftests never share a box
  [ -f "$SCEN/$name/solution.sh" ] || { echo "FAIL $name: no solution.sh"; return 1; }
  boot "$name" || { echo "FAIL $name: boot/break failed"; teardown; return 1; }
  cx bash /usr/local/lib/drill/run-check >/tmp/st.$$.$name 2>&1 && errs+=("check PASSES on the broken box (false positive)")
  cx bash /usr/local/lib/drill/run-check >/dev/null 2>&1 && errs+=("check flaky: passed on 2nd call")
  local t
  for t in "$SCEN/$name"/traps/*.sh; do
    [ -f "$t" ] || continue
    boot "$name" || { errs+=("re-boot for trap $(basename "$t") failed"); continue; }
    docker exec -u root "$NS" bash "/drill/traps/$(basename "$t")" >/dev/null 2>&1
    cx bash /usr/local/lib/drill/run-check >/dev/null 2>&1 && errs+=("wrong fix '$(basename "$t")' is ACCEPTED by check")
  done
  boot "$name" || { errs+=("re-boot for solution failed"); teardown; printf 'FAIL %s: %s\n' "$name" "${errs[*]}"; return 1; }
  docker exec -u tech -w /home/tech "$NS" bash /drill/solution.sh >/tmp/st.sol.$$.$name 2>&1 || errs+=("solution.sh exited non-zero: $(tail -3 /tmp/st.sol.$$.$name | tr '\n' ' ')")
  out=$(cx bash /usr/local/lib/drill/run-check 2>&1) || errs+=("check FAILS after solution.sh: $(echo "$out" | grep FAIL | sed 's/\x1b\[[0-9;]*m//g' | tr -s ' ' | tr '\n' ';')")
  rm -f /tmp/st.$$.$name /tmp/st.sol.$$.$name
  teardown
  if [ ${#errs[@]} -eq 0 ]; then echo "ok   $name"; return 0; fi
  printf 'FAIL %s\n' "$name"; printf '       - %s\n' "${errs[@]}"; return 1
}

cmd_selftest() {
  need_docker; ensure_image
  local list=("$@") s bad=0
  [ ${#list[@]} -gt 0 ] || mapfile -t list < <(scenarios)
  local nolab=() lab=()
  for s in "${list[@]}"; do have "$s" || die "no scenario '$s'"; [ "$(meta "$s" LAB)" = 1 ] && lab+=("$s") || nolab+=("$s"); done
  say "selftest: ${#nolab[@]} standalone (parallel x4), ${#lab[@]} lab (serial)"
  local tmp; tmp=$(mktemp -d)
  export ST_RUN=$$
  export -f selftest_one boot custom_prompt side_up cx cexists crunning teardown meta have fmt say die scenarios
  export HERE IMAGE SCEN LABLIB DATA c_b c_g c_r c_y c_d c_0
  if [ ${#nolab[@]} -gt 0 ]; then
    printf '%s\n' "${nolab[@]}" | xargs -P4 -I{} bash -c 'selftest_one {} > '"$tmp"'/{}.out 2>&1; echo $? > '"$tmp"'/{}.rc'
  fi
  for s in "${lab[@]}"; do selftest_one "$s" > "$tmp/$s.out" 2>&1; echo $? > "$tmp/$s.rc"; done
  for s in "${list[@]}"; do cat "$tmp/$s.out"; [ "$(cat "$tmp/$s.rc" 2>/dev/null || echo 1)" = 0 ] || bad=$((bad + 1)); done
  rm -rf "$tmp"
  echo; [ $bad -eq 0 ] && echo "${c_g}selftest: all ${#list[@]} scenarios OK${c_0}" || { echo "${c_r}selftest: $bad of ${#list[@]} FAILED${c_0}"; exit 1; }
}

cmd_help() { cat <<EOF
${c_b}drill.sh${c_0}  Linux break-fix drills (Docker, real systemd, real breakage)

  ./drill.sh list [-v]                 scenarios, level, your best time (-v: tags + titles, which spoil)
  ./drill.sh run <name> [--root] [--ssh]
                                       break a fresh box and drop you in it (as tech, with sudo;
                                       --ssh = enter over real ssh to 127.0.0.1:2222, --root = console as root)
  ./drill.sh random [--level N] [--area A] [--tag T] [--no-lab] [--ssh]
                                       least-recently-done scenario (areas: ${AREAS[*]})
  ./drill.sh menu [--ssh]              pick an area + level, then a random drill from it
  ./drill.sh session [N] [filters]     N random drills back to back (default 5), then your log
  ./drill.sh attach                    re-enter a drill whose terminal you lost (clock keeps running)
  ./drill.sh log                       your history: best/last times, hints, recent runs
  ./drill.sh review [N|name|list]      the path you took in the last drill: every command, time, exit status
  ./drill.sh selftest [name...]        prove every scenario breaks AND fixes (check fails -> solution.sh -> check passes)
  ./drill.sh build | clean             rebuild image | remove drill containers + lab

inside the box:  ticket   hint   check   playbook   solution   timer   answer "<diagnosis>"   next
env: DRILL_NS (container name)  DRILL_PRIVILEGED=1 (cgroup v1 hosts)  DRILL_HOME (log dir, default $DATA)
EOF
}

main() {
  local cmd=${1:-help}; shift || true
  case $cmd in
    run)      cmd_run "$@" ;;
    random)   cmd_random "$@" ;;
    session)  cmd_session "$@" ;;
    menu)     need_docker; cmd_menu "$@" ;;
    attach)   cmd_attach "$@" ;;
    list|ls)  cmd_list "$@" ;;
    log)      cmd_log ;;
    review)   cmd_review "$@" ;;
    selftest) cmd_selftest "$@" ;;
    build)    need_docker; docker rmi -f "$IMAGE" >/dev/null 2>&1; ensure_image; say "built $IMAGE" ;;
    up)       need_docker; ensure_image; boot "${1:?scenario}" && say "'$1' is up in container '$NS'  (docker exec -it -u tech $NS bash -l)" ;;
    clean)    cmd_clean ;;
    help|-h|--help) cmd_help ;;
    *) if have "$cmd"; then cmd_run "$cmd" "$@"; else cmd_help; die "unknown command '$cmd'"; fi ;;
  esac
}
main "$@"
