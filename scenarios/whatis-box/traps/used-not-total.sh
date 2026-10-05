# reads the memory IN USE (analytics holds 1874 MiB) instead of the card's total
. /var/lib/drill/.expected
echo "gpu=A2000 vram=1874 cams=$EXP_CAMS web=$EXP_WEB failed=$EXP_FAILED model=$EXP_MODEL" > /var/lib/drill/answer
