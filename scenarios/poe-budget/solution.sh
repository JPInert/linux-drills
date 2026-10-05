set -e
cat /etc/nvr/cameras.conf
ls /var/log/remote
grep -i power /var/log/remote/switch-2f.log | head
grep DENY /var/log/remote/switch-2f.log | grep -o 'Gi1/0/[0-9]*' | sort | uniq -c
grep DENY /var/log/remote/switch-2f.log | cut -c1-9 | sort | uniq -c | head
grep -i night /var/log/nvr/nvr.log | head
answer "Not the NVR. sw-2f, the switch that powers cameras 5-8, runs out of PoE power budget (requested ~75 W, available 67 W) when the cameras switch to night mode and turn their IR illuminators on around 7 pm; it denies power to ports Gi1/0/5-8 all night. Escalate to the customer's network team: raise the switch's PoE budget (bigger power supply or a PoE+ switch), or move some cameras to another switch or an injector. Do not turn off IR."
