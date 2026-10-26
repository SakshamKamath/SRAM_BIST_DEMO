#!/usr/bin/env python3
"""Run the VAD baseline checks with a pinned OSEDA image and bounded builds."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
MACRO = "RM_IHPSG13_1P_512x32_c2_bm_bist"
IMAGE = "-2026.09"


def sources():
    common = ROOT / "vendor/common_cells"
    files = [common / "cf_math_pkg.sv", ROOT / "vendor/obi/obi_pkg.sv",
             ROOT / "vendor/croc/croc_pkg.sv", ROOT / "vendor/croc/user_pkg.sv"]
    files += [common / (name + ".sv") for name in
              ("sync", "binary_to_gray", "gray_to_binary", "spill_register_flushable",
               "spill_register", "cdc_fifo_gray")]
    files += [ROOT / "rtl" / name for name in
              ("vad_frame_sram.sv", "ping_pong_buffer.sv", "vad_core.sv",
               "i2s_top_rx.v", "i2s_cdc_wrapper.sv", "vad_subsystem.sv", "vad_csr_wrapper.sv")]
    return files


def includes():
    return ["-I" + str(ROOT / name) for name in
            ("vendor/common_cells/include", "vendor/obi/include", "rtl/include")]


def run(command, log, records, marker=None):
    start = time.monotonic()
    with log.open("w") as output:
        result = subprocess.run(command, cwd=ROOT, stdout=output, stderr=subprocess.STDOUT, timeout=300)
    records.append({"command": command, "cwd": str(ROOT), "exit_code": result.returncode,
                    "seconds": round(time.monotonic() - start, 2),
                    "log": str(log.relative_to(ROOT))})
    if result.returncode:
        print(log.read_text()[-8000:])
        raise RuntimeError(f"Check failed (exit {result.returncode}); see {log}")
    if marker is not None and marker not in log.read_text():
        raise RuntimeError(f"Missing required success marker {marker!r}; see {log}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("phase", choices=("all", "sim", "synth", "lint"), nargs="?", default="all")
    args = parser.parse_args()
    reports = ROOT / "reports"
    reports.mkdir(exist_ok=True)
    records = []
    summary = reports / (args.phase + "_checks.json")
    if summary.exists():
        summary.unlink()  # Invalidate previous success before starting another run.
    # Keep only reports and the small synthesized netlist; remove build products.
    scratch = Path("/scratch") / os.environ.get("USER", "unknown") / "tmp"
    if not scratch.parent.is_dir() or not os.access(scratch.parent, os.W_OK):
        scratch = Path(tempfile.gettempdir())
    scratch.mkdir(exist_ok=True)
    if shutil.disk_usage(scratch).free < 512 * 1024 * 1024:
        raise RuntimeError(f"Need at least 512 MiB free at {scratch}")
    functional = ROOT / "vendor/ihp13/RM_IHPSG13_1P_core_behavioral_bm_bist.v"
    macro = ROOT / "vendor/ihp13" / (MACRO + ".v")
    sim_sources = [str(p) for p in sources() + [functional, macro]]
    base = ["oseda", IMAGE, "verilator", "--timing", "--assert", "-DFUNCTIONAL",
            "-Wno-TIMESCALEMOD", "-Wno-DECLFILENAME", str(ROOT / "scripts/lint.vlt")] + includes()
    try:
        with tempfile.TemporaryDirectory(prefix="vad_sram_", dir=scratch) as build_root:
            if args.phase in ("all", "lint"):
                run(base + ["--lint-only", "--top-module", "vad_csr_wrapper"] + sim_sources,
                    reports / "lint.log", records)
                print("PASS: baseline RTL lint")
            if args.phase in ("all", "sim"):
                reference = str(Path(build_root) / "test_vad_reference")
                run(["oseda", IMAGE, "cc",
                     "-std=c11", "-Wall", "-Wextra", "-Werror", "-I" + str(ROOT / "sw"),
                     str(ROOT / "tests/test_vad_reference.c"), "-o", reference],
                    reports / "reference_build.log", records)
                if not Path(reference).is_file():
                    raise RuntimeError("C compiler did not produce the reference executable")
                run(["oseda", IMAGE, reference],
                    reports / "reference.log", records, "PASS test_vad_reference")
                print("PASS: C software reference and comparator boundaries")
                for length in (2, 3, 320, 512):
                    name = f"datapath_{length}"
                    build = Path(build_root) / name
                    run(base + ["--binary", "-j", "2", "--Mdir", str(build),
                                "--top-module", "tb_vad_datapath", f"-GFRAME_SIZE={length}"]
                        + sim_sources + [str(ROOT / "tests/tb_vad_datapath.sv")],
                        reports / (name + "_build.log"), records)
                    run(["oseda", IMAGE, str(build / "Vtb_vad_datapath")], reports / (name + ".log"), records, f"PASS tb_vad_datapath FRAME_SIZE={length}")
                    print(f"PASS: SRAM and VAD datapath, FRAME_SIZE={length}")
                    shutil.rmtree(build)
                build = Path(build_root) / "obi"
                run(base + ["--binary", "-j", "2", "--Mdir", str(build),
                            "--top-module", "tb_vad_obi"] + sim_sources
                    + [str(ROOT / "tests/tb_vad_obi.sv")], reports / "obi_build.log", records)
                run(["oseda", IMAGE, str(build / "Vtb_vad_obi")], reports / "obi.log", records, "PASS tb_vad_obi")
                print("PASS: OBI registers and integrated I2S capture")
            if args.phase in ("all", "synth"):
                # Blackbox the actual PDK macro rather than synthesizing its simulation array.
                read = "read_slang --top vad_csr_wrapper --blackboxed-module " + MACRO
                read += " -DFUNCTIONAL " + " ".join(includes())
                read += " " + " ".join(str(p) for p in sources() + [functional, macro])
                netlist = reports / "vad_csr_wrapper.json"
                script = read + "; synth -top vad_csr_wrapper -noabc; check; stat; write_json " + str(netlist)
                run(["oseda", IMAGE, "yosys", "-m", "slang", "-p", script],
                    reports / "synth.log", records)
                design = json.loads(netlist.read_text())
                cells = [cell for module in design["modules"].values()
                         for cell in module.get("cells", {}).values()]
                cuts = sum(cell["type"] == MACRO for cell in cells)
                memories = [cell["type"] for cell in cells if cell["type"].startswith("$mem")]
                if cuts != 2 or memories:
                    raise RuntimeError(f"Expected two SRAM macros and no inferred arrays: {cuts=}, {memories=}")
                print("PASS: synthesis retains exactly two SRAM macros; no inferred frame arrays")
            fingerprints = {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
                            for p in sources() + list((ROOT / "tests").glob("*.sv")) + [ROOT / "tests/test_vad_reference.c", ROOT / "sw/vad_reference.h"]}
            (reports / (args.phase + "_checks.json")).write_text(json.dumps(
                {"image": "2026.09", "checks": records, "source_sha256": fingerprints}, indent=2) + "\n")
    finally:
        (reports / (args.phase + "_commands.json")).write_text(json.dumps(records, indent=2) + "\n")


if __name__ == "__main__":
    main()
