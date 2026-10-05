set -e
adb kill-server                              # 1. wipe the server's stale table
adb connect 10.50.0.77                       # 2. re-add the hub by hand (starts the server; port defaults to 5555)
adb devices | grep -q '10.50.0.77:5555.device'   # 3. the STATE column must say 'device'
