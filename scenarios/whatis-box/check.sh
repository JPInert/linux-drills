. /usr/local/lib/drill/lib.sh
. /var/lib/drill/.expected
a=$(cat /var/lib/drill/answer 2>/dev/null)
if [ -z "$a" ]; then bad "no answer yet. Run: answer \"gpu=... vram=... cams=N web=PORT failed=UNIT model=FILE\""; finish; exit; fi
get() { printf '%s\n' "$a" | grep -oiE "(^|[ ;,])$1=[^ ;,]+" | head -1 | sed -E 's/^[ ;,]//' | cut -d= -f2- | tr 'A-Z' 'a-z'; }
g=$(get gpu); v=$(get vram); c=$(get cams | tr -dc 0-9); w=$(get web | tr -dc 0-9); f=$(get failed); m=$(get model)
case "$g" in *a2000*) ok "gpu model" ;; *) bad "gpu=${g:-<missing>} is not the model nvidia-smi reports" ;; esac
case "$v" in 12288|12288mib|12gb|12g|12gib) ok "total GPU memory" ;; *) bad "vram=${v:-<missing>} is not the card's TOTAL memory in MiB" ;; esac
[ "$c" = "$EXP_CAMS" ] && ok "camera count" || bad "cams=${c:-<missing>} is not what the analytics service is configured for"
[ "$w" = "$EXP_WEB" ] && ok "web UI port" || bad "web=${w:-<missing>} is not the port nvr-web is listening on"
f=${f%.service}
[ -n "$EXP_FAILED" ] && [ "$f" = "$EXP_FAILED" ] && ok "failed unit" || bad "failed=${f:-<missing>} is not the service systemd lists as failed"
m=${m##*/}
[ "$m" = "$(echo "$EXP_MODEL" | tr 'A-Z' 'a-z')" ] && ok "configured model file" || bad "model=${m:-<missing>} is not the file the analytics config loads"
finish
