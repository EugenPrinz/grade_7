#!/usr/bin/env bash
# Прогон симуляции: texlua (Lua 5.3) из TeX Live или любой lua5.3.
# usage: test/run.sh [cycles] [seed]
set -euo pipefail
cd "$(dirname "$0")"
LUA=$(command -v lua5.3 || command -v texlua || command -v lua)
mkdir -p out && cd out
CYC=${1:-300}; SEED=${2:-1}
for sc in normal rawkeys smallhatch midstart noise t2screen lowstock iface iface-nome iface-dry; do
  "$LUA" ../sim.lua ../../degasser.lua "$sc" "$CYC" "$SEED" | tail -1
done
