# Cadence flow (Genus → Innovus → Tempus, gsclib045)

The same measurement as the open-source flow (`syn/flow.sh` + `syn/pnr.tcl`), run with commercial
tools and the Cadence GPDK045 standard-cell library (gsclib045):

| step | tool | what it gives |
|---|---|---|
| `src` | `syn/prepare_src.sh` | the variant's RTL (patches / overlays applied), `files.f`, `base.sdc` |
| `genus` | Genus | gate netlist at the slow corner, **hierarchy kept** (no auto-ungroup, no boundary optimization) |
| `sta_synth` | Tempus | T_min per instruction class on the Genus netlist (ideal clock, no wire RC) |
| `innovus` | Innovus | floorplan → place → optDesign → CCOpt → route → post-route opt; a `STAGE` line after each step |
| `sta_routed` | Tempus | T_min per instruction class on the routed netlist + SPEF, propagated clock |
| `summary` | `summary.sh` | `summary.txt`: numbers only |

The per-instruction constraints are the ones of `syn/sta_mode.tcl`, written for a hierarchical
netlist. Case analysis is on `iN/alu_control/ALUoperation[2:0]` and
`iN/SCDP/instruction_fetch/branch`, and the false paths go through `iN/SCDP/data_memory/read_data`
and `iN/SCDP/alu/{result,zero}`. Flip-flop groups come from Genus register names
(`Registers_reg`, `Memory_reg`, `buf*_to_*`, pipeline `if_id_*` … `mem_wb_*`; anything else is PC).
With hierarchy kept, the T_direct path (ALU → MemToReg → RF) uses all 32 bits. The Yosys flow
has to skip bits 2..6.

> These scripts were written without access to the Cadence tools and have not been run yet.
> The Tcl logic was checked with stubbed commands only. Expect to fix tool-version details on the
> first run: the `-no_gui` / `-batch` options and attribute names. The `WARN` and `ERROR` lines
> in the logs show where.

## Run

```bash
# 1. library names (site, tie, clock buffers, fillers) against your copy of gsclib045
export GSCLIB=/path/to/gsclib045          # directory containing lef/ timing/ qrc/
syn/cadence/check_lib.sh                  # fix any MISS with env vars (see setup.tcl)

# 2. relaxed target first: T_min = PERIOD - WNS is the structural delay of the netlist
PERIOD=200 syn/cadence/run.sh baseline
PERIOD=25  syn/cadence/run.sh recip
PERIOD=15  syn/cadence/run.sh recip+pipe
PERIOD=15  syn/cadence/run.sh recip+zero_cmp+pipe

# 3. then a target ~15 % below the synth T_min of step 2, to see what timing-driven
#    optimization recovers (as syn/pnr.tcl does with repair_timing)
PERIOD=<0.85 x T_min> syn/cadence/run.sh recip

# single steps, e.g. re-run only the routed STA and the summary
PERIOD=25 syn/cadence/run.sh recip "sta_routed summary"
```

Options (environment variables):
- `CORNERS="slow fast"`: the default is slow only.
- `MODES="none div"`: the default is all 7 classes, and `none` for `*pipe*`.
- `GENUS` / `INNOVUS` / `TEMPUS`: override the tool command lines.

Outputs go to `build/cadence/<variant>/`.

## What leaves the server

Only `build/cadence/<variant>/summary.txt`. It holds T_min, Fmax, cell count, area and the FF
groups at the ends of the worst path. It has no cell names and no path details.

gsclib045 is Cadence's generic 45 nm teaching library, not a foundry process. It is still
licensed, so these stay on the server and out of this repository:
- the .lib / .lef / QRC files;
- the netlists, DEF and SPEF;
- the full timing and area reports.

Check your lab's rules before publishing even the summary numbers.
