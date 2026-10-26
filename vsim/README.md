# QuestaSim flow (MBIST)

How to build the software, compile the RTL and run simulations with `run_vsim.sh`,
including MBIST fault injection and the chip-level testbench.

## Quick start

```bash
oseda bash                      # environment with the RISC-V toolchain and QuestaSim

cd sw && make clean && make     # build all test programs -> sw/bin/...
cd ../vsim
./run_vsim.sh --build --run ../sw/bin/test/test_mbist.hex
```

Expected output (no faults):

```
[UART] Starting MBIST
[UART] MBIST finished: 0, errors: 0
[JTAG] Simulation finished: SUCCESS
```

## `run_vsim.sh` options

| Option | What it does |
|---|---|
| `--build` | Compiles tech models (`compile_tech_func.tcl`: std cells, SRAM macro, IO pads), then the RTL and both testbenches (`compile_rtl.tcl`) into `work/` |
| `--run BINARY` | Runs `BINARY` (a `.hex`) in batch mode, writes `reports/run_vsim.log`, then runs the port check |
| `--run-gui BINARY` | Same, in the QuestaSim GUI (with `+acc` for signal visibility) |
| `--tb NAME` | Testbench for `--run`/`--run-gui`: `tb_croc_soc` (default) or `tb_croc_chip` |
| `--plusarg +ARG` | Extra simulator plusarg for `--run`/`--run-gui`, repeatable (`+bscan_test`, `+obi_jtag_test`) |
| `--mbist-fault` | With `--build`: SRAM uses the fault-injection model (see below) |
| `--techfunctional` | Only affects `--flist` (Bender targets). `--build` always compiles the tech models |
| `--flist` | Regenerates `compile_rtl.tcl` with Bender. **Overwrites the hand edits** in that file (SEM_PROJ files, `MBIST_FAULT` switch, `tb_croc_chip`) |
| `--build-netlist` | Compiles the post-synthesis netlist |
| `-n`, `--dry-run` | Prints the commands without running them |
| `-v`, `--verbose` | Prints the commands while running them |

Options can be combined; actions run in the order given. Environment variables
`TB=...`, `MBIST_FAULT=1` and `VSIM=...` work as well.

```bash
./run_vsim.sh --build                                             # compile only
./run_vsim.sh --run ../sw/bin/helloworld.hex                      # run on existing build
./run_vsim.sh --build --tb tb_croc_chip --run ../sw/bin/test/test_mbist.hex
./run_vsim.sh --tb tb_croc_chip --run-gui ../sw/bin/test/test_mbist.hex
```

**When to rebuild:** after any RTL change, and when switching `--mbist-fault` on or off.
Switching `--tb` needs no rebuild (both testbenches are compiled).

## Testbenches

| `--tb` | Top | Notes |
|---|---|---|
| `tb_croc_soc` | `croc_soc` | Default. Fastest |
| `tb_croc_chip` | `croc_chip` (IO pads + boundary-scan TAP) | JTAG goes through the boundary-scan TAP first; `croc_vip` is told about it via `ExtraIrLenBefore`/`ExtraDrBitsBefore` |

Both load the binary over JTAG, wake the core and wait for `main()` to return.
The return value is reported as `SUCCESS` (0) or `FAIL (return code ...)`.

## MBIST tests

`sw/test/test_mbist.c` runs MBIST on **macro 1** (SRAM bank 1, `0x1000_0800`–`0x1000_0FFF`)
and prints every failing address it reads from the error FIFO.

- MBIST is destructive: the tested bank is all zeros afterwards.
- Only macro 1 can be tested from software. Bank 0 holds the program and stack
  (`test_mbist` is linked with its stack at `0x1000_0800`). Test macro 0 over JTAG.
- `main()` returns `-3` (`FFFFFFFD`) when faults were found, so the testbench then
  reports `FAIL (return code 0x7ffffffd)`. That is the expected result with faults.

### Fault injection

```bash
./run_vsim.sh --mbist-fault --build --run ../sw/bin/test/test_mbist.hex
```

The build then uses `tc_sram_impl_fault.sv` with the fault model
(`rtl/RM_IHPSG13_1P_core_behavioral_bm_bist_fault_model.v`) instead of
`tc_sram_impl_mod.sv`. The log shows
`[MBIST-FAULT] ... fault injection ENABLED (bank 1)`.

Faults are set in
`rtl/SEM_PROJ_RTL/integrate_optimised_redundancy/mbist_fault_cfg_pkg.sv`
(rebuild after editing):

```systemverilog
localparam int unsigned FaultBank = 1;                  // bank that gets the faults

function automatic row_mask_t saf0_init();              // stuck-at-0
  row_mask_t m = '{default: '0};
  m = add_addr_fault(m, 32'h1000_0828, 32'hFFFF_FFFF);  // by CPU byte address
  m = add_word_fault(m, 11, 32'h0000_0001);             // by word index (0..511)
  m[200] |= 64'h1;                                      // by macro row (raw 64-bit mask)
  return m;
endfunction
```

- One function per fault type: `saf0_init`, `saf1_init`, transition (`MASK_TF_01/10`),
  read (`MASK_RDF`, `MASK_IRF`, `MASK_DRDF`) and write-disturb (`MASK_WDF`).
- Each bank is a 256 x 64 macro holding two words per row, bit-interleaved: word `w`
  is row `w/2`, even words on bits `[2i]`, odd words on bits `[2i+1]`.
  `add_word_fault`/`add_addr_fault` do this mapping.
- Byte address of word `w` in bank `b`: `0x1000_0000 + b*0x800 + w*4`.
- The default package gives 7 errors (one FIFO pause) at `0x1000_0828`, `0x1000_082C`
  and `0x1000_0CB0`.

To go back to the normal SRAM: `./run_vsim.sh --build` (without `--mbist-fault`).

## Boundary-scan test

```bash
./run_vsim.sh --build --tb tb_croc_chip --plusarg +bscan_test --run ../sw/bin/test/test_bscan.hex
```

Only on `tb_croc_chip` (the boundary-scan TAP is in `croc_chip`). The testbench drives
the boundary-scan TAP over JTAG; `sw/test/test_bscan.c` is the core side.

34 checks:

| Part | Area | Check |
|---|---|---|
| A (before program load) | Instructions | BYPASS chain = 5 bits (bndscan 2, obi_jtag 2, DMI 1); IR capture value `0000`; unused opcodes 4..15 act as BYPASS |
| | Chain length | SAMPLE/PRELOAD, EXTEST, INTEST: 44 bits (BSR 40 + 4) |
| | SAMPLE inputs | GPIO pattern and inverse; walking 1 and walking 0 on every testbench-driven GPIO pin (56 patterns); uart_rx 0 and 1; testmode 0 |
| | SAMPLE outputs | uart_tx/status/unused cells = core outputs; shifting/updating all 1s leaves the pins alone |
| | EXTEST outputs | Walking 1 and walking 0 over uart_tx, status, unused0..3 (12 patterns) |
| | EXTEST inputs | GPIO input pads are not driven by the BSR (no contention), and still capture the pins |
| | TAP reset | Test-Logic-Reset (TMS) and TRST release EXTEST; afterwards bndscan is in BYPASS |
| B (test_bscan running) | SAMPLE | Core drives `0xA5` on gpio[15:8]; the BSR captures it |
| | EXTEST with the core | BSR drives gpio[15:8] over the core (20 patterns); the cells still capture the core output; core inputs unaffected |
| | INTEST | Core reads gpio[23:16] from the BSR while the pins carry the inverse (13 patterns, seen in the echo on gpio[15:8]); the cells capture the core outputs |
| | BYPASS | Core drives / reads the pins again |

Not testable in this setup: driving `testmode` (it changes reset/clock behaviour of the
core), INTEST on uart_rx (the program does not use the UART), telling gpio 4..7 cells apart
from 0..3 (board loopback), EXTEST turning a GPIO into an output (the BSR has no
output-enable cells), IDCODE (the bndscan TAP has none).

Results are `[JTAG-TEST] PASS/FAIL` lines and `[JTAG-TEST] All N checks passed`. Failures
are `$error`s; the final `SUCCESS`/`FAIL` line is the return value of the program only.

BSR cells: `[0]` uart_rx, `[1]` testmode, `[2]` uart_tx, `[3]` status, `[4..7]` unused0..3,
`[8..39]` gpio0..31. Instructions: BYPASS 0, SAMPLE/PRELOAD 1, EXTEST 2, INTEST 3.
`--plusarg` passes any `+ARG` to the simulator and can be repeated.

## OBI JTAG isolation test

```bash
./run_vsim.sh --build --tb tb_croc_chip --plusarg +obi_jtag_test --run ../sw/bin/test/test_mbist.hex
# both JTAG tests together:
./run_vsim.sh --tb tb_croc_chip --plusarg +bscan_test --plusarg +obi_jtag_test --run ../sw/bin/test/test_bscan.hex
```

Runs over JTAG right after `jtag_init`, while the core sleeps in the bootrom; any program
works. obi_jtag TAP instruction `XcnctIsolation` (IR 1) puts the OBI cuts around the main
crossbar on TCK and in one scan chain, and takes the crossbar address map from JTAG.

DR chain (TDI -> TDO): isolation register (288 bits: 4 address rules, `en_default_idx`,
`default_idx`) -> TDO stage -> cuts at managers 0..3 (A 71 + R 35 bits) -> cuts at
subordinates 0..4 (A 73 + R 37 bits). A cut cell holds channel data only (no valid):
Capture loads the cut input, Update drives the cut output.

| Check | How |
|---|---|
| Scan chain | A pattern needs exactly 1266 TCK cycles from TDI to TDO (incl. bndscan and DMI bypass) |
| Routing | A write injected into the cut of manager 3 (core instr) is captured only by the subordinate cut it decodes to: periph, user, SRAM bank 0/1, error (unmapped) |
| JTAG address map | Same with the two SRAM banks swapped in the scanned address map |
| JTAG default index | Unmapped address goes to periph when `default_idx` is set to periph |
| Back to functional | After isolation, the `0x1234_5678` write/read over the crossbar and the program run |

Why manager 3: no manager requests during the test, so every subordinate arbiter passes the
A channel of its highest-index input (manager 3). Its demux sends the request to the
decoded subordinate and `'0` to the others. The subordinate-side `aid` is
`{manager index, aid}`.

## Port connection check

After every `--run`, `reports/run_vsim.log` is scanned for vopt
"Missing connection for port" warnings (`vopt-2718`):

- Pad power pins (`iovdd`, `iovss`, `vdd`, `vss`) are counted and ignored. `croc_chip`
  leaves them unconnected on purpose, like upstream Croc (the pad ring connects them in layout).
- Any other missing port is listed as `[WARNING][VSIM] Port check: ...` with file and line.

The warnings themselves are not suppressed. vopt only prints them when it re-optimizes
the design, so a run on an unchanged build may report nothing to check.

## Logs

| File | Content |
|---|---|
| `reports/compile_rtl.log`, `.rpt` | `--build` output and error/warning summary |
| `reports/run_vsim.log` | `--run` output |
| `croc.vcd` | Waveform of the top level, `tb_croc_soc` only (`TRACE_WAVE`). For `tb_croc_chip` use `--run-gui` |

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `Failed to find design unit 'tb_croc_chip'` | `work/` was built before the testbench existed: run `--build` |
| `Module 'sg13cmos5l_IOPadIn' is not defined` (or `MUX2X2`, `RM_IHPSG13_...`) | Tech models missing from `work/`: run `--build` |
| Hangs after `Starting MBIST` / at the first `printf` | Old binary: rebuild with `cd sw && make clean && make`. In the `.dump`, `_start` must set `sp` with `auipc sp` / `addi sp,sp,...`, not `addi sp,gp,...` |
| Very slow run | Keep `-t 1ns` (set by the script); UART output at 115200 baud takes ~1.7 ms simulated time per line |
| `NUM_ERRORS: unbound variable` with `-n` | Harmless in dry-run mode only |
