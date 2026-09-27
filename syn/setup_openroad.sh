#!/usr/bin/env bash
# Install OpenROAD (litex-hub conda build, via micromamba) and the Nangate45 LEFs it needs,
# for syn/pnr.tcl. The liberty is the same Nangate45 typical file the OpenSTA flow uses.
# usage: syn/setup_openroad.sh [tools dir, default build/tools]   (run syn/setup_tools.sh first)
set -euo pipefail
TOOLS=$(mkdir -p "${1:-build/tools}" && cd "${1:-build/tools}" && pwd)
MM=$TOOLS/micromamba
export MAMBA_ROOT_PREFIX=$TOOLS/mamba

if [ ! -x "$MM" ]; then
  curl -fsSL -o "$MM" https://github.com/mamba-org/micromamba-releases/releases/latest/download/micromamba-linux-64
  chmod +x "$MM"
fi
[ -x "$TOOLS/openroad-env/bin/openroad" ] || \
  "$MM" create -y -p "$TOOLS/openroad-env" -c litex-hub -c main openroad

PDK=$TOOLS/nangate45
mkdir -p "$PDK"
RAW=https://raw.githubusercontent.com/The-OpenROAD-Project/OpenROAD/master/test/Nangate45
for f in Nangate45_tech.lef Nangate45_stdcell.lef; do
  [ -s "$PDK/$f" ] || curl -fsSL -o "$PDK/$f" "$RAW/$f"
done
[ -s "$PDK/Nangate45_typ.lib" ] || gunzip -c "$TOOLS/OpenSTA/examples/nangate45_typ.lib.gz" > "$PDK/Nangate45_typ.lib"

"$TOOLS/openroad-env/bin/openroad" -version
