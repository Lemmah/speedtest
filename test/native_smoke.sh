#!/bin/sh
set -eu

port="${SPEEDTEST_SMOKE_PORT:-19876}"
output="${TMPDIR:-/tmp}/speedtest-smoke-$$.txt"
agent_log="${TMPDIR:-/tmp}/speedtest-agent-$$.log"

cleanup() {
  if [ -n "${agent_pid:-}" ]; then
    kill "$agent_pid" 2>/dev/null || true
    wait "$agent_pid" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

./build/speedtest-agent --bind 127.0.0.1 --port "$port" >"$agent_log" 2>&1 &
agent_pid=$!
sleep 1
./build/speedtest test "127.0.0.1:$port" --duration 0.5 --streams 2 --samples 4 >"$output"

grep -q "Idle" "$output"
grep -q "Download loaded" "$output"
grep -q "Upload loaded" "$output"
grep -q "Download.*Mbps" "$output"
grep -q "Upload.*Mbps" "$output"
cat "$output"

# The same native agent must accept a complete second test without restart.
./build/speedtest test "127.0.0.1:$port" --duration 0.2 --streams 1 --samples 2 >/dev/null
