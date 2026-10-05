set -e
printf 'nameserver 10.50.0.254\nsearch facility.lan\n' | sudo tee /etc/resolv.conf >/dev/null
sleep 1
