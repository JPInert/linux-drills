# the Linux reflex: rfkill acts on THIS laptop's radios, never on the hub's modem
rfkill list || true
rfkill unblock all || true
rfkill list || true
adb devices || true
