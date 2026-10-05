. /usr/local/lib/drill/lib.sh
a=$(tr 'A-Z' 'a-z' < /var/lib/drill/answer 2>/dev/null)
if [ -z "$a" ]; then bad "no answer yet. Run: answer \"<the cause, the number that proves it, who does what>\""; finish; exit; fi
# drop negated advice first ("do not replace the camera" is the RIGHT answer)
pos=$(printf '%s\n' "$a" | sed -E "s/(\bnot|n't|\bno|\bnever|\bdont|\binstead of|\brather than|\bwithout)\b[^.,;]{0,25}(replac|reboot|restart|rma|swap|order)[a-z]*//g")
if printf '%s\n' "$pos" | grep -qE "(replac|swap|rma|order)[a-z]* (the |a |that |this )?(new )?(camera|cam ?0?7|unit)|replacement|new camera|(camera|cam) ?0?7? (is )?(faulty|defective|bad|broken|dying|dead)|(reboot|restart)[a-z]* (the )?(nvr|box|server)"; then
  bad "the answer blames the camera or the NVR: what does camera7's own status say about its uptime and its link?"
fi
printf '%s\n' "$a" | grep -qE 'rssi|signal|dbm|-[78][0-9]|interfer|retr(y|ies)|noise|snr|neighbo|congest' \
  && ok "answer names the weak / noisy WiFi link, with the evidence" \
  || bad "answer does not say what is wrong with camera7's link (what does its status say about the signal?)"
printf '%s\n' "$a" | grep -qE 'access.?point|\baps?\b|channel|wire|cabl|ethernet|poe|relocat|\bmov|extender|mesh|survey' \
  && ok "answer says what should change (AP, channel or a cable)" \
  || bad "answer does not say what should be done about it, or by whom"
finish
