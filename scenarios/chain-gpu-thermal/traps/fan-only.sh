# fan back and quiet mode disabled, but the 40 W cap is still on the card
systemctl disable gpu-quiet
gpu-fan --auto
sleep 6
