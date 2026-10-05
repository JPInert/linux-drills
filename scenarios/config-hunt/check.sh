. /usr/local/lib/drill/lib.sh
. /var/lib/drill/.expected
a=$(cat /var/lib/drill/answer 2>/dev/null)
if [ -z "$a" ]; then bad "no answer yet. Run: answer \"file=/etc/nvr/... line=N value=N\""; finish; exit; fi
get() { printf '%s\n' "$a" | grep -oE "(^|[ ;,])$1=[^ ;,]+" | head -1 | sed -E 's/^[ ;,]//' | cut -d= -f2-; }
f=$(get file); l=$(get line | tr -dc 0-9); v=$(get value | tr -dc 0-9)
case "$f" in "$EXP_FILE"|"$(basename "$EXP_FILE")") ok "right file" ;; *) bad "file=${f:-<missing>} is not the file whose assignment the NVR ends up using" ;; esac
[ "$l" = "$EXP_LINE" ] && ok "right line number" || bad "line=${l:-<missing>} is not the line of that assignment"
[ "$v" = "$EXP_VALUE" ] && ok "right value" || bad "value=${v:-<missing>} is not the effective value"
finish
