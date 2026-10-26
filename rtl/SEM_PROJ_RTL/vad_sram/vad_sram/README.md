# VAD with internal SRAM: development starting point

This project is a starting point for developing an example of functional testing and software access to hardware state. The immediate work is to decide how the example should work, implement it, and document the main choices briefly. Once developed, it can become an aid for students.

The motivation is practical: when hardware has a bug, software needs enough access to locate the problem and work around the faulty part while continuing to use the working parts.

## Current design

The voice-activity detector (VAD) follows this path:

**I2S audio capture → frame SRAM → energy and zero-crossing calculation → speech decision**

It is adapted from `submissions/vlsi2_21fs26`. The starting version has two explicit IHP single-port 512 × 32-bit SRAM macros. Each sample occupies the low 16 bits of a word; the default frame has 320 samples. Capture fills one bank while processing reads the completed bank. The SRAMs are currently **not address mapped**.

Software can set enable and thresholds through OBI, but cannot read samples, inject a frame, or read intermediate results. This makes it a useful starting point for investigating which additional access actually helps with testing and recovery.

| Offset | Existing register | Reset value |
| --- | --- | --- |
| `0x20` | Enable, bit 0 | 1 |
| `0x24` | Energy threshold | 17,435 |
| `0x28` | Zero-crossing threshold | 20 |

Offsets are relative to the peripheral base. The speech event is one clock cycle long and occurs when `enable && energy > energy_threshold && zero_crossings <= zcr_threshold`.

## Work to develop

- Choose a few concrete faults and identify the observations and controls needed to distinguish or work around them.
- Develop software access to useful boundaries, such as captured frames and intermediate features. Work out ownership, completion, and reset behavior before fixing the register interface.
- Demonstrate the chosen cases through software-visible accesses, with tests and short explanations of why each access exists and how it is used.

The interface and eventual teaching format remain design work. Keep documentation focused on the implemented example and its decisions. [Development notes](docs/development.md) record the main issues to investigate.

## Run the existing checks

With OSEDA 2026.09 installed, run:

```sh
make check
```

The Makefile uses `/usr/bin/python3.12`; override it with `make PYTHON=python3 check` if needed. Individual phases are `make lint`, `make sim`, and `make synth`.

Tests and a C reference are already provided. Logs and commands are retained in `reports/`; [validation notes](docs/validation.md) describe their scope. Dependency origins are recorded in `vendor/SOURCES.json`.
