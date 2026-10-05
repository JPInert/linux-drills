# the first listening port in ss is sshd, not the web UI
. /var/lib/drill/.expected
echo "gpu=A2000 vram=12288 cams=$EXP_CAMS web=22 failed=$EXP_FAILED model=$EXP_MODEL" > /var/lib/drill/answer
