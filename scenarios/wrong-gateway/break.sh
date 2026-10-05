. /drill-lab/baseline.sh
# the old router's address survived in a config: default route now points at a dead gateway
ip route replace default via 10.50.0.1
