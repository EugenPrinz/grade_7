#!/usr/bin/env bash
# Full test suite: unit tests, G1–G6 simulator, G7 simulator, G8 simulator, installer.
# usage: bash test/all.sh [cycles] [seed]
set -euo pipefail
cd "$(dirname "$0")/.."
LUA=$(command -v lua5.3 || command -v texlua || command -v lua)
export LUA_PATH="./?.lua;./?/init.lua;;"
CYC=${1:-25}; SEED=${2:-1}
for t in core_test manifest_test bindings_test dashboard_test main_test display_test parallel_test entrypoint_test; do
  "$LUA" "test/$t.lua"
done
"$LUA" test/units_sim.lua all "$CYC" "$SEED" | tail -1
"$LUA" test/g8_sim.lua | tail -1
bash test/run.sh "$CYC" "$SEED" | awk '{print} /провал [1-9]/ && !/lowstock|iface-dry/ {bad=1} END {exit bad}'
TMP=$(mktemp -d)
"$LUA" test/install_test.lua "$PWD" "$TMP/root" | tail -1
rm -rf "$TMP"
echo "test/all.sh: OK"
# END test/all.sh
