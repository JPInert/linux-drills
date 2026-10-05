. /usr/local/lib/drill/lib.sh
g() { adb --mock get "$1" 2>/dev/null; }
if [ "$(g derived/airplane)" = false ]; then ok "the hub's radio is powered (airplane mode is off)"; else bad "the hub's radio is still powered down (airplane mode is on)"; fi
sim=$(g derived/sim_state)
case $sim in LOADED|READY) ok "gsm.sim.state is $sim" ;; *) bad "gsm.sim.state is $sim" ;; esac
net=$(g derived/network_type)
if [ "$net" = LTE ]; then ok "gsm.network.type is LTE"; else bad "gsm.network.type is $net"; fi
ds=$(g derived/data_conn_state)
if [ "$ds" = 2 ]; then ok "mobile data is connected (rmnet_data0 is up)"; else bad "no mobile data connection (data state $ds, not connected)"; fi
finish
