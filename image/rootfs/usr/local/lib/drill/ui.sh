# shared look for the in-box commands (sourced by ticket, hint, playbook, run-check)
# 16/256-colour SGR only, box-drawing characters, no emoji. Cards are 76 columns wide.
# shellcheck shell=bash
case ${LANG:-}${LC_ALL:-} in *[Uu][Tt][Ff]-8*|*[Uu][Tt][Ff]8*) ;; *) export LANG=C.UTF-8 ;; esac
if [ -t 1 ] || [ -n "${DRILL_COLOR:-}" ]; then
  B=$'\e[1m' D=$'\e[2m' R=$'\e[0m' RED=$'\e[31m' GRN=$'\e[32m' YEL=$'\e[33m'
  BLU=$'\e[34m' MAG=$'\e[35m' CYA=$'\e[36m' WHT=$'\e[1;97m' ORG=$'\e[38;5;208m'
  ONRED=$'\e[1;97;41m' ONGRN=$'\e[1;30;42m'
else
  B='' D='' R='' RED='' GRN='' YEL='' BLU='' MAG='' CYA='' WHT='' ORG='' ONRED='' ONGRN=''
fi
UI_W=72          # text width inside "| " ... " |"
UI_C=$CYA        # border colour; callers set it per card

ui_len() { local s; s=$(printf '%s' "$1" | sed 's/\x1b\[[0-9;]*m//g'); echo "${#s}"; }
ui_rep() { local i s=''; for ((i = 0; i < $2; i++)); do s+=$1; done; printf '%s' "$s"; }

# ui_top "LEFT TITLE" ["right note"]    ->  ╭─ LEFT TITLE ─────────── right note ─╮
ui_top() {
  local l=" $1 " r=${2:+" $2 "} n
  n=$(( UI_W + 2 - 1 - $(ui_len "$l") - $(ui_len "$r") - 1 ))
  [ $n -lt 1 ] && n=1
  printf '%s╭─%s%s%s%s%s%s─╮%s\n' "$UI_C" "$R$B" "$l" "$R$UI_C" "$(ui_rep ─ $n)" "$R$D$r$R$UI_C" "" "$R"
}
ui_sep() { printf '%s├%s┤%s\n' "$UI_C" "$(ui_rep ─ $((UI_W + 2)))" "$R"; }
ui_bot() { printf '%s╰%s╯%s\n' "$UI_C" "$(ui_rep ─ $((UI_W + 2)))" "$R"; }
# ui_row "text with optional colour codes"   (caller keeps it <= UI_W visible columns)
ui_row() {
  local n; n=$(( UI_W - $(ui_len "$1") )); [ $n -lt 0 ] && n=0
  printf '%s│%s %s%*s %s│%s\n' "$UI_C" "$R" "$1" $n '' "$UI_C" "$R"
}
# ui_wrap "indent-label" "plain text" [colour]: word-wrap plain text into rows, label on the first
ui_wrap() {
  local lab=$1 txt=$2 col=${3:-} w pad first=1 ln
  w=$(( UI_W - ${#lab} )); pad=$(printf '%*s' ${#lab} '')
  while IFS= read -r ln; do
    if [ $first = 1 ]; then ui_row "$lab$col$ln$R"; first=0; else ui_row "$pad$col$ln$R"; fi
  done < <(printf '%s\n' "$txt" | fold -s -w "$w" | sed 's/ *$//')
}
# priority colour + word, from "P1".."P4"
ui_prio() {
  case $1 in
    P1*) printf '%s' "$ONRED P1 CRITICAL $R" ;;
    P2*) printf '%s' "$B$RED P2 HIGH $R" ;;
    P3*) printf '%s' "$B$YEL P3 MEDIUM $R" ;;
    P4*) printf '%s' "$B$CYA P4 LOW $R" ;;
    *)   printf '%s' "$B$1$R" ;;
  esac
}
