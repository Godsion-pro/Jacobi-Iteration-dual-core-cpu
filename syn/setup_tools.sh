#!/usr/bin/env bash
# Install the open-source toolchain used by syn/flow.sh (tested on Ubuntu 24.04, run as root).
#   yosys 0.33 (apt) | sv2v v0.0.12 (release binary) | OpenSTA + CUDD (source, pinned commits)
# Nangate45 slow/typ/fast liberty files come with OpenSTA under examples/.
#
# usage: syn/setup_tools.sh [TOOLS_DIR]      (default build/tools)
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
T=$(realpath -m "${1:-$ROOT/build/tools}")
OPENSTA_SHA=ef17b3fd81404d685d33ec65e0354c122d701e4d
CUDD_SHA=f54f533303640afd5dbe47a05ebeabb3066f2a25
mkdir -p "$T" && cd "$T"

# flex needs libfl-dev (FlexLexer.h); OpenSTA's cmake stops without it
apt-get update -q || echo "apt-get update reported errors (unreachable extra repos are fine if the install below succeeds)"
apt-get install -y -q --no-install-recommends \
  yosys cmake g++ make git curl unzip patch automake autoconf libtool \
  tcl-dev swig bison flex libfl-dev libeigen3-dev zlib1g-dev

fetch() {  # fetch <dir> <url> <sha>
  [ -d "$1/.git" ] && return
  git init -q "$1" && git -C "$1" remote add origin "$2"
  git -C "$1" fetch -q --depth 1 origin "$3" && git -C "$1" checkout -q FETCH_HEAD
}

[ -x sv2v-Linux/sv2v ] || {
  curl -sSL -o sv2v.zip https://github.com/zachjs/sv2v/releases/download/v0.0.12/sv2v-Linux.zip
  unzip -oq sv2v.zip && chmod +x sv2v-Linux/sv2v
}

fetch cudd https://github.com/ivmai/cudd.git "$CUDD_SHA"
[ -f cudd-install/lib/libcudd.a ] || (
  cd cudd && autoreconf -fi >/dev/null 2>&1
  ./configure -q --prefix="$T/cudd-install" && make -s -j"$(nproc)" && make -s install )

fetch OpenSTA https://github.com/The-OpenROAD-Project/OpenSTA.git "$OPENSTA_SHA"
# BUILD_TESTS=OFF: unit tests need GTest, which is not needed to run STA
cmake -S OpenSTA -B OpenSTA/build -DCUDD_DIR="$T/cudd-install" -DCMAKE_BUILD_TYPE=Release \
      -DBUILD_TESTS=OFF -DUSE_TCL_READLINE=OFF > cmake.log
cmake --build OpenSTA/build --target sta -j"$(nproc)" > build.log

echo "yosys : $(yosys -V)"
echo "sv2v  : $("$T"/sv2v-Linux/sv2v --version)"
echo "sta   : $("$T"/OpenSTA/build/sta -version)"
