# Behavioral models for the IHP13 tech cells, SRAM macros and IO pads.
# Sourced by run_vsim.sh --build on every build (compile_rtl.tcl needs them).
# Must run BEFORE compile_rtl.tcl.

set ROOT ".."

proc tech_vlog {desc args} {
    puts "INFO: compile_tech_func.tcl: $desc"
    if {[catch { vlog -incr -sv {*}$args }]} {
        puts "ERROR: compile_tech_func.tcl: $desc failed"
        return -code error "tech compile failed: $desc"
    }
}

# 1. Standard cells (INVX2, MUX2X2, ...)
tech_vlog "EZ130 8T standard cells" \
    "+define+TECHFUNCTIONAL" \
    "$ROOT/technology/verilog/ez130_8t.v"

# 2. SRAM macros: core model first, then the wrappers that instantiate it
#    (256x64: croc SRAM banks, 512x32: VAD frame buffers)
tech_vlog "SRAM macros 256x64 + 512x32 bm_bist" \
    "+define+TECHFUNCTIONAL" \
    "+define+FUNCTIONAL" \
    "+define+SIM" \
    "$ROOT/technology/verilog/RM_IHPSG13_1P_core_behavioral_bm_bist.v" \
    "$ROOT/technology/verilog/RM_IHPSG13_1P_256x64_c2_bm_bist.v" \
    "$ROOT/technology/verilog/RM_IHPSG13_1P_512x32_c2_bm_bist.v"

# 3. IO pads (sg13cmos5l_IOPad*), needed by croc_chip / tb_croc_chip
tech_vlog "SG13CMOS5L IO pads" \
    "$ROOT/technology/verilog/sg13cmos5l_io.v"