#!/usr/bin/env bash
#
# Multi-node routing through a Java TCPServerInterface acting as a transport hub.
#
# CLAUDE.md records this as a known issue: "Links go PENDING when clients try to
# connect through a TCP server". Nothing in the six-step plan covered it — every
# earlier step was two nodes on one hop. This is also the topology Qortal runs,
# and the first live exercise of the relay-side link-request MTU clamp
# (RNS/Transport.py:2058), which only runs on a transport node.
#
#   peer B  ---TCP--->  hub (enable_transport)  <---TCP---  peer A
#
# Peer A hosts the destination; peer B reaches it in two hops. A link is
# established end to end and a packet of exactly the negotiated MDU is echoed
# back as a digest, so a truncated or mis-routed frame cannot pass.
#
# Usage:  ./run.sh
#
# Everything runs on 127.0.0.1:42508. No external network is touched.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
WORK="$HERE/.work"
EXPECTED_MTU="${EXPECTED_MTU:-16384}"

PIDS=()
cleanup() { for p in "${PIDS[@]:-}"; do [[ -n "$p" ]] && kill "$p" 2>/dev/null; done; }
trap cleanup EXIT

say() { printf '\n=== %s ===\n' "$1"; }

mkdir -p "$WORK"
rm -f "$WORK"/*.log
rm -rf "$HERE"/*_config/storage

say "Preparing"
CP_FILE="$WORK/classpath.txt"
[[ -s "$CP_FILE" ]] || (cd "$REPO" && mvn -o -q dependency:build-classpath -Dmdep.outputFile="$CP_FILE") \
    || { echo "FAIL: classpath"; exit 1; }
(cd "$REPO" && mvn -o -q test-compile) || { echo "FAIL: test-compile"; exit 1; }
CP="$(cat "$CP_FILE"):$REPO/target/classes:$REPO/target/test-classes"

say "Starting the hub"
timeout 180 java -cp "$CP" examples.Step6IngressVictim "$HERE/hub_config" 150 > "$WORK/hub.log" 2>&1 &
PIDS+=($!)
for _ in $(seq 1 60); do
    grep -aq '\[step6-victim\] ready' "$WORK/hub.log" 2>/dev/null && break
    sleep 0.5
done
grep -aq '\[step6-victim\] ready' "$WORK/hub.log" || {
    echo "FAIL: the hub did not start"; grep -avE "DEBUG|TRACE" "$WORK/hub.log" | tail -15 | sed 's/^/  | /'; exit 1; }
echo "hub up on 127.0.0.1:42508 with transport enabled"

say "Starting peer A (hosts the destination)"
timeout 180 java -cp "$CP" examples.Step5FramingServer "$HERE/peer_a_config" > "$WORK/peer_a.log" 2>&1 &
PIDS+=($!)
DEST=""
for _ in $(seq 1 60); do
    DEST="$(grep -a 'destination <' "$WORK/peer_a.log" 2>/dev/null | grep -oE '<[0-9a-f]{32}>' | head -1 | tr -d '<>')"
    [[ -n "$DEST" ]] && break
    sleep 0.5
done
if [[ -z "$DEST" ]]; then
    echo "FAIL: peer A did not report a destination"
    grep -avE "DEBUG|TRACE" "$WORK/peer_a.log" | tail -15 | sed 's/^/  | /'; exit 1
fi
echo "peer A destination: $DEST"
sleep 6

say "Peer B links to peer A through the hub"
timeout 180 java -cp "$CP" examples.Step5FramingClient "$HERE/peer_b_config" "$DEST" "$EXPECTED_MTU" \
    > "$WORK/peer_b.log" 2>&1
RC=$?
grep -aE "^\[step5\]" "$WORK/peer_b.log" | sed 's/^/  /'
grep -aE "^\[step5-server\]" "$WORK/peer_a.log" | sed 's/^/  /'

say "Hub view"
grep -a "Clamped link MTU\|Clamping link MTU" "$WORK/hub.log" | sed -E 's/^.*- /  /' | head -2
echo "  hub path table at the end:"
grep -aE "^\[step6-victim\] t=" "$WORK/hub.log" | tail -1 | sed 's/^/    /'

say "Result"
if [[ $RC -eq 0 ]]; then
    echo "PASS — a link established and carried a full-MDU frame across two hops"
    echo "       through a Java TCPServerInterface transport hub."
else
    echo "FAIL — see $WORK/. A link stuck in PENDING is the shape of the issue"
    echo "       CLAUDE.md records for this topology."
fi
exit $RC
