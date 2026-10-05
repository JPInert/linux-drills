# helpers for scenario check.sh (sourced; runs as root)
PASS_N=0; FAIL_N=0
ok()   { printf '  \033[1;32m[PASS]\033[0m %s\n' "$*"; PASS_N=$((PASS_N+1)); }
bad()  { printf '  \033[1;31m[FAIL]\033[0m %s\n' "$*"; FAIL_N=$((FAIL_N+1)); }
info() { printf '  \033[36m[INFO]\033[0m \033[2m%s\033[0m\n' "$*"; }
# want "description" cmd args...   -> PASS if the command succeeds
want() { local d=$1; shift; if "$@" >/dev/null 2>&1; then ok "$d"; else bad "$d"; fi; }
# finish: prints "N/M passing" and returns 0 only when nothing failed (end check.sh with it)
finish() {
  local t=$((PASS_N + FAIL_N)) c='\033[1;32m'
  [ "$FAIL_N" -gt 0 ] && c='\033[1;33m'
  [ "$t" -gt 0 ] && printf '  \033[2m%s\033[0m\n  %b%d/%d passing\033[0m\n' \
    '--------------------------------' "$c" "$PASS_N" "$t"
  [ "$FAIL_N" -eq 0 ]
}
