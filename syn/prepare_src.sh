#!/usr/bin/env bash
# Build a synthesis source directory for a variant: rtl/*.sv with `include lines removed
# (the RTL includes shared modules twice), then each variant part applied in order
# (variants/<p>.patch, or the files of variants/<p>/), plus the synthesis wrapper.
#
# usage: syn/prepare_src.sh <variant> <outdir>     variant: baseline | <part>[+<part>...]
set -euo pipefail
VARIANT=$1
OUT=$2
ROOT=$(cd "$(dirname "$0")/.." && pwd)

strip_includes() { grep -v '^[[:space:]]*`include' "$1" > "$2/$(basename "$1")"; }

rm -rf "$OUT"; mkdir -p "$OUT"
for f in "$ROOT"/rtl/*.sv; do strip_includes "$f" "$OUT"; done
if [ "$VARIANT" != baseline ]; then
  for p in ${VARIANT//+/ }; do
    if   [ -f "$ROOT/variants/$p.patch" ]; then patch -s -d "$OUT" -p1 < "$ROOT/variants/$p.patch"
    elif [ -d "$ROOT/variants/$p" ]; then for f in "$ROOT"/variants/$p/*.sv; do strip_includes "$f" "$OUT"; done
    else echo "unknown variant part $p" >&2; exit 1; fi
  done
fi
cp "$ROOT/syn/syn_top.sv" "$OUT/"

# file list in dependency order (interface first, wrapper last) for tools without `include
{
  echo "$OUT/exchange_if.sv"
  for f in "$OUT"/*.sv; do
    case $(basename "$f") in exchange_if.sv|top.sv|syn_top.sv) ;; *) echo "$f" ;; esac
  done
  echo "$OUT/syn_top.sv"
} > "$OUT/files.f"
