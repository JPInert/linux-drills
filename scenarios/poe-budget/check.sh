. /usr/local/lib/drill/lib.sh
a=$(tr 'A-Z' 'a-z' < /var/lib/drill/answer 2>/dev/null)
if [ -z "$a" ]; then bad "no answer yet. Run: answer \"<the cause, what triggers it at 7, who does what>\""; finish; exit; fi
# drop negated advice first ("do not turn off the IR" is fine)
pos=$(printf '%s\n' "$a" | sed -E "s/(\bnot|n't|\bno|\bnever|\bdont|\binstead of|\brather than|\bwithout)\b[^.,;]{0,25}(replac|reboot|restart|rma|swap|disabl|turn|switch)[a-z]*( off)?//g")
if printf '%s\n' "$pos" | grep -qE "(replac|swap|rma)[a-z]* (the |these |those |all )?(new )?(cameras?|cams?\b)|(reboot|restart)[a-z]* (the )?(nvr|box|server)|(disabl|turn(ing)? off|switch(ing)? off)[a-z]*( the)? (ir|infrared|night)"; then
  bad "the answer replaces cameras, reboots the NVR or switches the night vision off: that is not a fix for a care home at night"
fi
printf '%s\n' "$a" | grep -qE 'poe|power|budget|watt|[0-9] ?w\b' \
  && ok "answer names the PoE power budget" \
  || bad "answer does not say what the switch is running out of (read its log at 7 pm)"
printf '%s\n' "$a" | grep -qE '\bir\b|infrared|illuminat|night|dark|dusk' \
  && ok "answer names what triggers it (IR on at dusk)" \
  || bad "answer does not say what changes at 7 pm (compare the NVR log at the same minute)"
printf '%s\n' "$a" | grep -qE 'raise|increase|bigger|larger|upgrade|poe\+|another switch|second switch|other switch|injector|split|\bmov|more power|power supply|psu|(replac|swap)[a-z]* (the )?switch|escalat|network team|\bit (team|dept|department|staff)|to it\b|their it\b|customer.s it\b' \
  && ok "answer says what should change on the switch side" \
  || bad "answer does not say what should be done about it, or by whom"
finish
