set -e
adb shell cmd connectivity airplane-mode disable                 # switch 1: power the modem back up
adb shell svc data enable                                        # switch 2: mobile data is a separate toggle
sleep 1
adb shell getprop | grep -q 'gsm.sim.state.*LOADED'              # verify what the modem reports
