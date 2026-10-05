# sourced by lab scenarios' break.sh (root, inside the box): the HEALTHY network state
install -o tech -g tech -m 0644 /dev/stdin /home/tech/install-sheet.txt <<'SHEET'
NORTHGATE GARAGE - CAMERA VLAN INSTALL SHEET                      (rev C, commissioned by J. Ortiz)

  edge-nvr-03      10.50.0.50/24   gateway 10.50.0.254    DNS 10.50.0.254
  camera1          10.50.1.31      camera1.facility.lan   web UI :80 (accepts the NVR, 10.50.0.50, only)

  retired:         old site router 10.50.0.1 (switch swap; it no longer routes anything)
SHEET
printf 'nameserver 10.50.0.254\nsearch facility.lan\n' > /etc/resolv.conf
ip route replace default via 10.50.0.254
