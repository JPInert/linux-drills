# airplane mode and the mobile-data toggle are persistent settings: a reboot brings both back unchanged
adb reboot
sleep 1
adb wait-for-device
sleep 1
