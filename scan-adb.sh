#!/usr/bin/env bash
# Finds the TCP port where adbd answers on a projector/TV, then connects to it.
# Usage: ./scan-adb.sh <ip> [first-port] [last-port]
set -euo pipefail

ip=${1:?usage: $0 <ip> [first-port] [last-port]}
first=${2:-1}
last=${3:-65535}

echo "Scanning $ip ports $first-$last ..." >&2
open=$(seq "$first" "$last" | xargs -P 400 -I{} sh -c \
  "timeout 0.5 bash -c '</dev/tcp/$ip/{}' 2>/dev/null && echo {}" | sort -n || true)
[ -n "$open" ] || { echo "No open ports found." >&2; exit 1; }

for port in $open; do
  adb connect "$ip:$port" >/dev/null 2>&1 || true
  # Non-ADB services accept the TCP connection but stay "offline".
  if [ "$(timeout 3 adb -s "$ip:$port" get-state 2>/dev/null)" = device ]; then
    echo "ADB found on $ip:$port"
    exit 0
  fi
  adb disconnect "$ip:$port" >/dev/null 2>&1 || true
done

echo "Open ports ($(echo $open | tr '\n' ' ')), but none answered as ADB." >&2
exit 1
