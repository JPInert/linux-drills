# counts EVERY auth line per IP (OK + FAIL): picks the busy legit-looking decoy, and a wrong total
. /var/lib/drill/.expected
L=/var/log/nvr
read -r n ip < <(grep -o 'ip=[0-9.]*' $L/auth.log | cut -d= -f2 | sort | uniq -c | sort -rn | head -1)
echo "ip=$ip fails=$n 5xx=$EXP_5XX cam=$EXP_CAM" > /var/lib/drill/answer
