# Existing checks

`make check` passes with OSEDA 2026.09, Verilator 5.052, and Yosys 0.69 with Slang.

The checks cover RTL lint, the C reference, SRAM/VAD processing at frame lengths 2, 3, 320, and 512, concurrent capture and processing, reset cases, and OBI register accesses. The integrated I2S test uses constant input levels. Synthesis retains exactly two SRAM macro cells and no inferred memory arrays.

Commands, source hashes, and results are in `reports/all_checks.json`; individual logs are in `reports/`. Simulations require explicit PASS markers.

These checks establish a working starting point. Arbitrary I2S word/channel alignment, CDC/reset signoff, full-chip software execution, and physical implementation still need investigation if they become part of the example.
