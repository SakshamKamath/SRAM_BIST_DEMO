# Development notes

Use a small set of faults to guide the design. For example, reading a captured frame could distinguish an input-alignment problem from an arithmetic problem; injecting a known frame could test processing independently of capture; reading intermediate features could let software replace the final decision. Choose and demonstrate the cases that make the example useful.

Work out these details when adding access:

- Who owns each frame bank, and what happens if software holds it while another frame arrives?
- How does software know a frame or result is complete, including when speech is not detected?
- How can software read a coherent 48-bit energy result over a 32-bit bus?
- What remains usable when one stage is bypassed, and what does reset invalidate?

Current behavior to account for:

- Samples must be at least four system-clock cycles apart. There is no frame ownership handshake or processing backpressure.
- SRAM reads are synchronous. Contents are not reset; processing starts after a complete frame is captured.
- The inherited sample reconstruction is `{raw_sample[14], raw_sample[14:0]}`. Investigate the receiver alignment before changing it; the C reference currently matches it.
- The register decoder uses address bits 7:0, so higher offsets alias existing registers. Plan the decode when adding a memory window.
- Enable and thresholds are used at the decision. Disabling the speech event does not stop capture or feature calculation.

Tests may inspect internal signals, but the eventual demonstrations need to use accesses available to software. Document the chosen behavior and its reason briefly alongside the implementation.
