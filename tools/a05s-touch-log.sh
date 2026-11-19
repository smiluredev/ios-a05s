#!/bin/sh
# Host side of the A05s live kernel log across a phone reboot.
#   sudo tools/a05s-touch-log.sh [LOGFILE]
# The phone is 192.168.7.2 on its CDC-ECM interface; this keeps 192.168.7.1/24
# on the host interface whenever it (re)appears and receives UDP 5140.
# Run it before rebooting the phone so the touch probe (~45 s after boot) is caught.
set -eu
log=${1:-build-a05s/logs/a05s-touch.log}
mac=02:00:5e:77:ee:01
mkdir -p "$(dirname "$log")"

(
	while :; do
		if ip -o link | grep -qi "$mac"; then
			ifname=$(ip -o link | grep -i "$mac" | awk -F': ' '{print $2}' | cut -d@ -f1)
			ip addr replace 192.168.7.1/24 dev "$ifname" 2>/dev/null || true
			ip link set "$ifname" up 2>/dev/null || true
		fi
		sleep 1
	done
) &
loop=$!
trap 'kill "$loop" 2>/dev/null' EXIT INT TERM

echo "waiting for the phone's log on udp/5140 (host 192.168.7.1, phone 192.168.7.2); file: $log" >&2
nc -ukl 5140 | tee -a "$log"
