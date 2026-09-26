#!/usr/bin/env python3
"""Minimal assembler for the dual-core Jacobi CPU ISA (as implemented in rtl/).

Added in the 2026 portfolio cleanup to re-verify the hand-encoded instruction ROMs.

ISA as the RTL decodes it (differences from textbook MIPS are marked *):
  R  : add sub and or slt mul* div*   op rd, rs, rt      000000 rs rt rd 00000 funct
       funct: add 100000  sub 100010  and 100100  or 100101  slt 101010
              mul 100001* div 100011*  (Q15.16 multiply / divide in alu.sv)
  I  : lw/sw rt, imm(rs)   imm = byte offset (data memory indexes address[31:2])
       addi rt, rs, imm
       beq rs, rt, target   imm = (target - (PC+4)) >> 2
       bne                  * decoded identically to beq by control_unit.sv (latent)
  J  : j target             * 26-bit field holds the BYTE address; the fetch unit
                              builds {PC+4[31:28], field[25:2], 2'b00}
  X  : rec*                 opcode 010101: copy peer's exchange buffer into Memory[10..11]
Registers: $zero = r0 (not hard-wired), $tN = r(N+1), rN also accepted.

Usage:
  python3 sw/asm.py sw/core0.s                                   # print ROM lines
  python3 sw/asm.py sw/core0.s --check rtl/instruction_memory_0.sv
"""

import argparse
import re
import sys

FUNCT = {"add": 0b100000, "sub": 0b100010, "and": 0b100100, "or": 0b100101,
         "slt": 0b101010, "mul": 0b100001, "div": 0b100011}
OPCODE = {"lw": 0b100011, "sw": 0b101011, "addi": 0b001000,
          "beq": 0b000100, "bne": 0b000101, "j": 0b000010, "rec": 0b010101}


def reg(tok):
    tok = tok.strip().lower()
    if tok in ("$zero", "$0", "r0"):
        return 0
    m = re.fullmatch(r"\$t(\d+)", tok)
    if m:
        return int(m.group(1)) + 1
    m = re.fullmatch(r"\$?r(\d+)", tok)
    if m:
        return int(m.group(1))
    raise ValueError(f"bad register {tok!r}")


def num(tok, labels):
    tok = tok.strip()
    return labels[tok] if tok in labels else int(tok, 0)


def parse(path):
    """Return [(pc, mnemonic, operands, lineno)] and label table."""
    insts, labels, pc = [], {}, 0
    for lineno, raw in enumerate(open(path, encoding="utf-8"), 1):
        line = re.split(r"#|//", raw, maxsplit=1)[0].strip()
        while ":" in line:
            name, line = line.split(":", 1)
            labels[name.strip()] = pc
            line = line.strip()
        if not line:
            continue
        parts = line.split(None, 1)
        ops = [o.strip() for o in parts[1].split(",")] if len(parts) > 1 else []
        insts.append((pc, parts[0].lower(), ops, lineno))
        pc += 4
    return insts, labels


def encode(pc, mn, ops, labels):
    if mn in FUNCT:
        rd, rs, rt = (reg(o) for o in ops)
        return (rs << 21) | (rt << 16) | (rd << 11) | FUNCT[mn]
    if mn in ("lw", "sw"):
        m = re.fullmatch(r"(-?\w+)\((.+)\)", ops[1].replace(" ", ""))
        imm, rs = int(m.group(1), 0), reg(m.group(2))
        return (OPCODE[mn] << 26) | (rs << 21) | (reg(ops[0]) << 16) | (imm & 0xFFFF)
    if mn == "addi":
        return (OPCODE[mn] << 26) | (reg(ops[1]) << 21) | (reg(ops[0]) << 16) | (num(ops[2], labels) & 0xFFFF)
    if mn in ("beq", "bne"):
        off = (num(ops[2], labels) - (pc + 4)) >> 2
        return (OPCODE[mn] << 26) | (reg(ops[0]) << 21) | (reg(ops[1]) << 16) | (off & 0xFFFF)
    if mn == "j":
        return (OPCODE[mn] << 26) | (num(ops[0], labels) & 0x3FFFFFF)
    if mn == "rec":
        return OPCODE[mn] << 26
    raise ValueError(f"unknown mnemonic {mn!r}")


def rom_words(sv_path):
    words = {}
    for line in open(sv_path, encoding="utf-8"):
        m = re.search(r"Memory\[(\d+)\]\s*<?=\s*32'b([01_\s]+);", line)
        if m:
            words[int(m.group(1))] = int(re.sub(r"[_\s]", "", m.group(2)), 2)
    return words


def fmt(w):
    b = f"{w:032b}"
    return "_".join([b[0:6], b[6:11], b[11:16], b[16:21], b[21:26], b[26:32]])


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("src")
    ap.add_argument("--check", metavar="SV", help="compare against Memory[] words in an RTL ROM file")
    args = ap.parse_args()

    insts, labels = parse(args.src)
    words = [encode(pc, mn, ops, labels) for pc, mn, ops, _ in insts]

    if not args.check:
        for i, ((pc, mn, ops, _), w) in enumerate(zip(insts, words)):
            print(f"Memory[{i}] = 32'b{fmt(w)}; // {mn} {', '.join(ops)}")
        return

    rom = rom_words(args.check)
    bad = 0
    for i, ((pc, mn, ops, lineno), w) in enumerate(zip(insts, words)):
        if rom.get(i) != w:
            bad += 1
            got = fmt(rom[i]) if i in rom else "missing"
            print(f"MISMATCH Memory[{i}] (PC={pc}, {args.src}:{lineno} {mn} {', '.join(ops)})\n"
                  f"   asm : {fmt(w)}\n   rom : {got}")
    extra = sorted(set(rom) - set(range(len(words))))
    if extra:
        bad += len(extra)
        print(f"MISMATCH ROM has extra words at {extra}")
    print(f"{args.check}: {len(words)} words checked, {bad} mismatch(es)")
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
