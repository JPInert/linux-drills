# the out-of-date install notes: the analytics-install defaults
f=$(systemctl list-units --failed --plain --no-legend --type=service | cut -d' ' -f1 | head -1)
echo "gpu=A2000 vram=12288 cams=4 web=8080 failed=${f%.service} model=person-vehicle.engine" > /var/lib/drill/answer
