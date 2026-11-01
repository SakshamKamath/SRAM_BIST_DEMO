# Verification of the DFT and observability additions: slide content

Items marked **[fill in]** still need numbers from a fresh run (see the end of the file). Slides built from this: `verification.pptx` (`verification_pptx.py`).

---

## Slide A: Verification strategy (overview)

**Title:** Verifying the DFT and observability additions

| Level | What runs | Testbenches |
|---|---|---|
| Unit | DUT plus a behavioural SRAM fault model | `tb_march_bist_top`, `tb_jtag_march`, `tb_vad_sram_dbg` |
| SoC | Real C code on CVE2, plus a JTAG driver in the testbench | `tb_croc_soc`, `tb_croc_jtag_march` |
| Chip (with pads) | The full chip seen from the pins: JTAG, GPIO, UART | `tb_croc_chip` (`+bscan_test`, `+obi_jtag_test`) |

- **Self-checking:** every check prints PASS or FAIL, and the run ends with "N of M checks failed".
- **Two access paths for each feature:** from the CPU over OBI (software) and from the tester (JTAG), the way it's used in silicon.
- **No regressions:** the original Croc tests (`helloworld` and others) still pass with all additions in place.

**Say:** "Each feature was tested on its own first, then inside the SoC, then at the pins, which is how it gets used on the tester."

---

## Slide B: Boundary scan (BSC)

**Title:** Boundary scan: SAMPLE, EXTEST, INTEST

- **Setup:** the JTAG chain is TDI → bndscan TAP (IR 4) → obi_jtag TAP (IR 2) → DMI TAP (IR 5) → TDO.
- **Boundary scan register (40 cells):** uart_rx, testmode, uart_tx, status, unused0..3, gpio0..31.
- **Part A, pins only, core idle:**
  - Chain length in each mode: BYPASS = 5 bits; SAMPLE, EXTEST and INTEST = 40 + 4. Unused opcodes fall back to BYPASS.
  - **SAMPLE:**
    - the cells capture the pin values, using walking 1/0 patterns on the GPIOs;
    - shifting in all 1s does not disturb the outputs.
  - **EXTEST:**
    - the BSR drives uart_tx, status and unused0..3 (walking 1/0);
    - input pads are not driven but still capture.
  - **Release:** a TAP reset via TMS, TRST, or BYPASS returns the pins to the core.
- **Part B, with the core running `test_bscan.c`:**
  - The core sets GPIO[15:8] as outputs and echoes GPIO[23:16] onto them.
  - **EXTEST:** the BSR overrides the core on gpio[15:8].
  - **INTEST:** the core reads its inputs from the BSR, not the pins. The echo shows the BSR pattern, proving the core is isolated from the pads.
- **Result:** **all 34 checks pass** (`tb_croc_chip +bscan_test`, Questa, 31 Oct). With `+obi_jtag_test` in the same run: 52 of 52.

**Say:** "INTEST shows we can test the core without trusting the board, and EXTEST shows we can test the board without trusting the core."

---

## Slide C: March BIST

**Title:** SRAM March BIST: fault injection and SoC integration

- **Algorithm:** March MSS (18N) in 6 stages: ⇕(w0); ⇑(r0,r0,w1,w1); ⇑(r1,r1,w0,w0); ⇓(r0,r0,w1,w1); ⇓(r1,r1,w0,w0); ⇕(r0).
- **Unit test (`tb_march_bist_top`):** a behavioural SRAM model with injected faults:
  - stuck-at-1, bit 0 at address 0x2A;
  - transition fault 0→1, bits [3:0] at address 10;
  - read-disturb fault, bit 31 at address 16.

  It prints DONE or FAIL; the error FIFO is not read out and nothing is compared automatically.
- **JTAG path (`tb_jtag_march`, `tb_croc_jtag_march`):**
  - start with INSTR_MBIST over JTAG;
  - wait for done/fail;
  - on FAIL, read the error-address FIFO out over JTAG (instruction ERRADDR_LOAD) and print each entry;
  - hand the bus back and wake the core.
- **Software path with injected faults (`run_vsim.sh --techfunctional --mbist-fault`, `test_mbist.c` on bank 1):**
  - stuck-at faults on words 10, 11 and 300 (set in `mbist_fault_cfg_pkg.sv`), giving 7 expected errors;
  - the 4-entry FIFO fills once, so the drain → resume path is exercised;
  - the addresses are printed over UART as byte addresses (0x1000_0828, 0x1000_082C, 0x1000_0CB0).
- **Software path (`test_mbist.c`, `test_vad_mbist.c`):**
  - started from soc_ctrl_regs at 0x0300_0000;
  - 4 macros: croc banks 0/1 and VAD banks 0/1;
  - the program lives in bank 0, so it only tests the bank it isn't running from.
  - The VAD test checks that both banks pass, the croc banks aren't started, and the VAD banks read back as all zeros through the VAD debug registers.
- **Result:** `test_vad_mbist` **passes on `tb_croc_soc` and `tb_croc_chip`**. Unit, JTAG and fault-injection results: **[fill in]**.
- **Gap:** error addresses are printed and checked by eye, not compared against an expected list. The VAD banks (macros 2/3) only had fault-free runs.

**Say:** "With faults injected, the failing addresses come out through both JTAG and software, including when the FIFO overflows and the march resumes."

---

## Slide D: Interconnect isolation (crossbar isolation)

**Title:** Isolating the OBI crossbar over JTAG

- **Mechanism:** the obi_jtag TAP instruction `XcnctIsolation` does three things:
  - switches the cuts around the crossbar onto TCK;
  - links them into one scan chain (4 managers × A/R, 5 subordinates × A/R);
  - loads the crossbar address map from a JTAG register.
- **Test (`+obi_jtag_test`, core asleep in the bootrom):** inject a request at manager cut 3, then capture it at all subordinate cuts. Only the cut that should receive it sees it.
  - **Default map:**
    - periph (0x0300_0000), user (0x2000_0000), SRAM bank 0 and bank 1;
    - an unmapped address (0x9000_0000) goes to the error subordinate.
  - **Map changed over JTAG:** with banks 0 and 1 swapped, requests are routed to the other bank.
  - **default_idx changed over JTAG:** unmapped addresses now go to periph.
  - **Release:** the crossbar returns to the system clock and the hard-wired map.
- **Sub access (JtagSubAccess = 1):** JTAG writes a word into SRAM bank 0 and reads it back; the error subordinate answers err = 1; each transaction reaches its subordinate exactly once; the word is then read over the debug path.
- **Result:** isolation only: **all 18 checks pass**; with sub access and the kept JTAG map: **all 25 checks pass** (Questa, 31 Oct 18:29). The isolation RTL was edited after that run, so rerun before quoting it as current.
- **Note:** that log ends with "FAIL (return code 0x1)". This is not the isolation test: afterwards the testbench runs `test_bscan.hex` without `+bscan_test`, and that program fails without the boundary-scan stimulus. Use `helloworld.hex` for this run.

**Say:** "This tests the crossbar's routing on its own, with no CPU and no memory involved, so a routing bug can't hide behind a broken core."

---

## Slide E: VAD observability and controllability

**Title:** Making the VAD visible and controllable

| Addition | How it was verified |
|---|---|
| SRAM debug port (0x2C–0x40): write, read, KICK, auto-increment | Write and read both banks; check auto-increment and bank select |
| Sticky SPEECH flag with W1C, plus IRQ_EN | The flag sets, holds and clears; the IRQ follows IRQ_EN |
| Interrupt trigger (SRAM_CMD.IRQ_TRIG) and read-back (SRAM_STATUS.IRQ) | Trigger with IRQ_EN off sets only the flag; enabling raises the line, masking hides it; the line rises the cycle after a trigger and drops after W1C; works outside debug mode |
| Last frame result: LAST_ENERGY/LAST_ZCR (0x44–0x4C), RW | Matches a model of the frame energy/ZCR; write/readback; byte-enable masking |
| EVAL command (gated by DBG_EN) | 7 cases: energy above/below threshold, upper energy bits, ZCR boundary (equal to threshold), VAD disabled, DBG_EN off |
| Priority | A real frame overwrites values written by software |

- **Testbench:** `tb_vad_sram_dbg` has a golden model of the frame (including the bit-15 sign fix).
- **Result:** **1095 checks, all pass** (Verilator 5.020, 1 Nov). Negative controls: the old RTL fails at the read-back check, RTL without the trigger fails at the trigger check.
- **SoC level:**
  - `test_vad_mbist` reads the SRAMs through the debug registers after BIST.
  - `test_vad_irq` fires the interrupt with IRQ_TRIG and checks it in the VAD status, the core's `mip` and the handler (taken once, acknowledged by W1C, masked when IRQ_EN is off): **SUCCESS** (Verilator 5.020). A copy with one wrong expectation reports FAIL 0xc as intended.
- **Testability (ATPG, same DEMO netlist):** registers reachable vs. cut off (OBI addr[6] tied to 0): pins-only fault coverage 28.3 % vs 17.0 %, DSP core 23.5 % vs 5.0 %; of the 2858 faults only detected with the registers, 1433 were not observed and 792 not controlled without them. Plots: `vad_atpg_ablation_coverage.png`, `vad_atpg_ablation_reasons.png`.

**Say:** "We can now put any frame into the SRAM, or any energy/ZCR value into the decision logic, and check the decision without a microphone. This splits the VAD into two halves that can be tested separately."

---

## Slide F (or slide 14): Summary

| Feature | Unit | SoC | Chip/pins | Status |
|---|---|---|---|---|
| Boundary scan | – | – | `tb_croc_chip +bscan_test` | 34 / 34 ✔ |
| March BIST | `tb_march_bist_top` (SAF, TF, RDF) | `test_mbist`, `test_vad_mbist` | `tb_croc_jtag_march`, `tb_croc_chip` | VAD MBIST ✔ |
| Crossbar isolation | – | – | `tb_croc_chip +obi_jtag_test` | 18 / 18 ✔, with sub access 25 / 25 ✔ (rerun pending) |
| VAD observability + interrupt | `tb_vad_sram_dbg` (1095 checks) | `test_vad_mbist`, `test_vad_irq` | – | ✔ |
| Regression | – | helloworld, print_config, clint, compute, gpio, obi_timer, soc_ctrl, uart, interrupts ✔ | helloworld ✔ | ✔ (test_idma not rerun) |

**Limitations to say honestly:**

- RTL simulation only: no gate-level simulation and no tester runs yet.
- The March unit test injects a few faults rather than every fault class (no coupling faults injected).
- Popping a non-empty VAD error FIFO through soc_ctrl hasn't been tested at SoC level.
- `test_interrupts` now passes (Verilator, 1 Nov). `test_idma` has not been rerun; leave it out of the "no regressions" claim until it is.
- Questa runs are from 31 Oct, before sub access became the default and before the VAD interrupt trigger; rerun the regression when the licence is back.

---

## Filling in the brackets

Each of these runs prints "N of M checks FAILED" or "all passed":

```
./run_vsim.sh --tb tb_croc_chip --plusarg +bscan_test --run ../sw/bin/test/test_bscan.hex
./run_vsim.sh --tb tb_croc_chip --plusarg +obi_jtag_test ...
```
