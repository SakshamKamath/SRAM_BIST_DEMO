# Crossbar (interconnect) isolation on Croc

Write-up to go with `xbar_isolation.pptx`. The numbers come from `tb_croc_chip +obi_jtag_test` (RTL simulation, QuestaSim) and the Yosys run `PROJ_NAME=croc_dft`.

## Why it is needed

Every load, store and instruction fetch in Croc passes through one OBI crossbar. When a bus access fails on silicon (a hang, wrong data, or an access that lands in the wrong place), the fault can sit in three places:

- **the manager:** the core, the debug module or the user domain;
- **the crossbar:** address decode, demux or arbitration;
- **the subordinate:** SRAM banks, peripherals or the VAD.

From the outside these look the same. We also cannot stop a running bus to look at it, and we cannot drive a test request into the crossbar unless the core is working.

## What we added

- **Cuts on every crossbar boundary:** a cut (spill register) sits at each of the 4 manager ports and each of the 5 subordinate ports. In normal mode the cuts are ordinary pipeline registers on the system clock.
- **A TAP, `obi_jtag`:** it sits in the JTAG chain after the boundary-scan TAP. It has a 2-bit IR: 0 is BYPASS, 1 is XcnctIsolation.
- **What XcnctIsolation does:**
  - A clock mux (`tc_clk_mux2`) moves the cuts onto TCK.
  - The cuts drive `ready = 0` upstream, so every manager stalls.
  - The cut outputs drive only what was shifted in.
  - The address map, `en_default_idx` and `default_idx` now come from a JTAG register instead of the hard-wired `CrocAddrMap`.
- **One DR chain, 1263 bits:**
  - the isolation register, 288 bits;
  - one TDO stage;
  - manager cuts 0–3;
  - subordinate cuts 0–4, with the cuts adding up to 974 bits.
  - From the chip's TDI to TDO it is 1266 bits, with the other TAPs in BYPASS.

| Ports | Index and name |
|---|---|
| Managers | 0 User, 1 Debug, 2 Core data, 3 Core instr |
| Subordinates | 0 Error, 1 Periph, 2 User/VAD, 3 SRAM bank 0, 4 SRAM bank 1 |

## How a test works

Each test takes two DR scans with the same vector:

1. **Shift and Update:** the isolation register gets the address map, and the A-channel cut of a manager gets a request, for example a write to 0x1000_0828. Update drives the request into the crossbar.
2. **Capture and Shift:** every subordinate cut captures what reached it. The result is shifted out at TDO and compared: only the expected subordinate may hold the request.

## How it helps debugging

1. **Is it the crossbar?** Inject a request at any manager boundary and see which subordinate boundary receives it. This needs no core, software or memory. A wrong destination points into the crossbar; a correct one points at the manager or the subordinate.
2. **Freeze and look:**
   - Entering isolation stalls every manager.
   - Capture then snapshots the request and response channels at all 9 boundaries.
   - After a hang, this shows which address and data were waiting at each port.
   - *Limits:* the chain holds channel data only, not valid or ready. This use has not been tested in simulation yet.
3. **What-if address map:**
   - Load another address map or default index from JTAG and repeat the routing test. This can confirm a suspected decode bug, or try a remap such as swapping the SRAM banks.
   - *Limit:* the JTAG map is used only while XcnctIsolation is selected. Outside isolation the register follows `CrocAddrMap`, so it cannot repair a chip at run time.
4. **Clean exit:** BYPASS or a TAP reset puts the cuts back on the system clock and restores the hard-wired map. The core then runs normally.

## Verification

`tb_croc_chip +obi_jtag_test` drives only the chip's JTAG pins. The core stays asleep in the bootrom during the test.

| Check | Result |
|---|---|
| Scan chain: a pattern comes out after exactly 1266 bits TDI → TDO | PASS |
| Hard-wired map: periph 0x0300_0000 → S1 | PASS |
| Hard-wired map: user 0x2000_0000 → S2 | PASS |
| Hard-wired map: bank 0 0x1000_0010 → S3 | PASS |
| Hard-wired map: bank 1 0x1000_0828 → S4 | PASS |
| Hard-wired map: unmapped 0x9000_0000 → S0 (error) | PASS |
| JTAG map, banks swapped: 0x1000_0828 → S3 | PASS |
| JTAG map, banks swapped: 0x1000_0010 → S4 | PASS |
| JTAG `default_idx` = periph: 0x9000_0000 → S1 | PASS |

**Result:** 9 of 9 checks pass.

After isolation is switched off, a JTAG write to the SRAM reads back correctly over the crossbar, and `helloworld` runs and prints "Hello World from Croc!". This is outside the 9 checks.

**Not covered yet:**
- a snapshot of live traffic (use 2);
- injecting on the response (R) channel;
- entering isolation while transactions are in flight.

Each injected request is judged by where its A channel is captured. The subordinate itself is not exercised, because its cut holds the injected data rather than passing it on.

Run with:
```
cd vsim
./run_vsim.sh --tb tb_croc_chip --plusarg +obi_jtag_test --run ../sw/bin/helloworld.hex
```

## Cost

From the Yosys report, IHP 130 nm, standard cells only:

- `obi_jtag_top` (TAP, isolation register and cuts): 138,519 µm². That is about 24 % of the chip's logic, about the size of the CPU core.
- Crossbar: 61,950 µm² without isolation, about 195,600 µm² with it. That is `obi_xbar` at 57,044 plus `obi_jtag_top`.
- Most of the cost is about 2,600 cut flip-flops and their scan muxes. Scanning only the address and control fields would shrink it considerably.

## Takeaways

- The crossbar can be tested on its own, from the existing JTAG pins, without the core.
- The address map and default routing can be changed from JTAG while testing.
- It switches off cleanly, and normal operation is unaffected afterwards.
- The cost is area: the scan cuts are the largest part of the DFT logic.
