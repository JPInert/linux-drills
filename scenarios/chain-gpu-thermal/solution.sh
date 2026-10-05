set -e
# stop quiet mode coming back at boot (keep the unit: the site's noise issue is real)
sudo systemctl disable gpu-quiet
# and undo what it did to the card right now
sudo nvidia-smi -pl 70
sudo gpu-fan --auto
answer "GPU was power-capped to 40 W and fan-capped to 25% by gpu-quiet (noise ticket HR-4471); thermal throttling in the afternoon made alerts late. Restored vendor 70 W and auto fan, disabled gpu-quiet. Noise must be fixed by facilities (closet door/insulation, move box), not by throttling the GPU." >/dev/null
sleep 6
