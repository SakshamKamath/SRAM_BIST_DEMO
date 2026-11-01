# Boundary scan on Croc

Write-up to go with `boundary_scan.pptx`. Items marked **[fill in]** need numbers from a fresh run.

## Why it is needed

After tape-out, three questions come up that the core alone cannot answer:

- **Is it the chip or the board?** A silent UART on the first board can be a bad solder joint, a wrong pin map, or a broken core. From the outside they look the same.
- **Pins we cannot probe.** There are 48 signal pins on a fine-pitch package. A probe on each is not practical, and a probe can only observe, never drive.
- **A core we cannot fully trust.** On Thomy (IIS, IHP130), synthesis flipped the reset values of control signals that were assigned through an array. The team needed scan access to force the right values.

Boundary scan (IEEE 1149.1) puts a scan cell between every signal pad and the core. From the five JTAG pins we can read every pin while the chip runs, drive every output pin, and feed the core any input pattern, all without firmware.

## What we added to Croc

- **40 boundary-scan cells:** uart_rx, testmode, uart_tx, status, unused0–3, gpio0–31. Bit 0 (uart_rx) is shifted out first.
- **No cell on** clk, rst_n, ref_clk or the JTAG pins.
- **Its own TAP**, first in the JTAG chain: TDI → Bndscan TAP → OBI-JTAG TAP → debug TAP → TDO.
- **A 4-bit instruction register:** 0 BYPASS, 1 SAMPLE/PRELOAD, 2 EXTEST, 3 INTEST. Every unused opcode selects BYPASS.

## How a cell works

Each cell has a shift flip-flop, an update flip-flop and a mux in front of the pad or core:

1. **Capture:** the pin value (or the core output) is copied into the shift FF.
2. **Shift:** one bit per TCK. A new pattern goes in at TDI while the captured values come out at TDO.
3. **Update:** the shifted-in values move to the update FFs together. In EXTEST or INTEST they drive the pin or the core.

In BYPASS and SAMPLE the mux keeps the functional path, so normal operation is untouched.

## The four instructions

| Instruction | What happens | Use it for |
|---|---|---|
| BYPASS (0) | The chip runs normally; the TAP is 1 bit long | Default state; reaching the other TAPs quickly |
| SAMPLE / PRELOAD (1) | Snapshot of every pin while the chip runs; also preloads safe values | Watching uart_tx, status and gpio live |
| EXTEST (2) | The BSR drives the output pins and captures the inputs; the core is cut off | Board test: shorts, opens, a wrong pin map |
| INTEST (3) | The BSR drives the core inputs and captures the core outputs; the pins are cut off | Testing the core without a working board |

## Examples of how it helps

1. **UART prints nothing.** SAMPLE uart_tx while the firmware runs. If the cell toggles, the core works and the fault is on the board. If it is stuck, look at the core. EXTEST can then toggle the pin directly for the scope.
2. **GPIO short on the board.** Walk a single 1 across the GPIO outputs under EXTEST and read the pins back through the input cells. A short shows the 1 on two pins; an open never shows it.
3. **Core needs known inputs.** Like the Thomy fix, but at the chip boundary: PRELOAD and INTEST force testmode or the GPIO inputs to known values from JTAG, whatever the board drives. (Boundary scan does not reach internal registers; that is what the internal scan chains are for.)
4. **Is the core alive?** In our test the core echoes gpio[23:16] onto gpio[15:8]. Under INTEST the echo returns the BSR pattern, not the pin values. This proves the core path works with nothing on the pins.

## Verification

`tb_croc_chip +bscan_test` together with `sw/test/test_bscan.c`. The testbench drives only the chip pins and JTAG, the way a tester would.

**Part A (pins only, core idle):**
- Chain length per instruction: BYPASS 5 bits; SAMPLE, EXTEST and INTEST 44 bits.
- Unused opcodes select BYPASS.
- SAMPLE: walking 1/0 on all 32 GPIO pins is captured.
- SAMPLE: shifting all 1s leaves the outputs alone.
- EXTEST: walking 1/0 on uart_tx, status and unused0–3.
- EXTEST: input pads are not driven, and they still capture.
- TMS reset, TRST and BYPASS all give the pins back to the core.

**Part B (core running test_bscan.c):**
- SAMPLE sees the core's outputs on gpio[15:8].
- EXTEST: the BSR overrides the core on gpio[15:8].
- INTEST: the core reads the BSR, not the pins.
- BYPASS: the core drives and reads the pins again.

**Result:** [fill in: X of Y checks pass], RTL simulation in QuestaSim.

Run with:
```
./run_vsim.sh --tb tb_croc_chip --plusarg +bscan_test --run ../sw/bin/test/test_bscan.hex
```

## Takeaways

- Separates chip faults from board faults without firmware.
- Every signal pin can be read and driven from 5 JTAG pins.
- The core can be tested on its own with INTEST.
- Cost: 40 cells and one TAP. Area: [fill in].
