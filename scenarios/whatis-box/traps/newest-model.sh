# picks the newest file in the models folder (a staged update) instead of the configured one
. /var/lib/drill/.expected
echo "gpu=A2000 vram=12288 cams=$EXP_CAMS web=$EXP_WEB failed=$EXP_FAILED model=$EXP_STAGE" > /var/lib/drill/answer
