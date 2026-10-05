# "have you tried turning it off and on": the permission stays revoked, so the service crashes again at boot
adb reboot
sleep 1
adb wait-for-device
sleep 10
