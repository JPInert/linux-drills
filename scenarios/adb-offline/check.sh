. /usr/local/lib/drill/lib.sh
HUB=10.50.0.77:5555
tbl=$(adb --mock get derived/devices 2>/dev/null)
want "adb server is running" test "$(adb --mock get server/running 2>/dev/null)" = true
if printf '%s\n' "$tbl" | grep -qxF -- "$(printf '%s\tdevice' "$HUB")"; then
  ok "$HUB is attached and its state is 'device'"
else
  st=$(printf '%s\n' "$tbl" | awk -F'\t' -v h="$HUB" '$1==h{print $2}')
  if [ -n "$st" ]; then bad "the hub $HUB is in the adb device list as '$st'"; else bad "the hub $HUB is not in the adb device list"; fi
fi
finish
