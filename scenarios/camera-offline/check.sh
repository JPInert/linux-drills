. /usr/local/lib/drill/lib.sh
a=$(cat /var/lib/drill/answer 2>/dev/null)
if [ -z "$a" ]; then bad "no answer recorded yet. Run: answer \"<diagnosis and next step>\""; finish; exit; fi
echo "$a" | grep -qiE 'camera|cam1|10\.50\.1\.31' && ok "answer names the camera as the fault" || bad "answer does not name the camera (what device is actually unreachable?)"
echo "$a" | grep -qiE 'power|poe|cable|switch|unplug|offline|down|dead|unreachable|on-?site|dispatch|escalat|physical|hardware' \
  && ok "answer says what is wrong / who acts next" || bad "answer does not say what should happen next (who acts, on what)"
finish
