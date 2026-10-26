#!/bin/bash
# Copyright (c) 2026 ETH Zurich and University of Bologna.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# Published with permission from Siemens.
# Siemens QuestaSim is available through EDA Higher Education Software Program
# https://www.sw.siemens.com/en-US/academic/educators/eda-higher-education-software/
#
# Authors:
# - Thomas Benz     <tbenz@iis.ee.ethz.ch>
#
# Modified: TECHFUNCTIONAL switch (IHP13 tech cells + SRAM macro models in RTL sim)


set -e  # Exit on error
set -u  # Error on undefined vars


################
# Setup
################
# Source environment
source "../env.sh"

VSIM=${VSIM:-questa-2023.4 vsim}

# 1 = RTL simulation with IHP13 cells and SRAM macro models (see --techfunctional)
TECHFUNCTIONAL=${TECHFUNCTIONAL:-0}

# 1 = SRAM banks use the fault-injection model (see --mbist-fault)
MBIST_FAULT=${MBIST_FAULT:-0}

# Testbench top for --run / --run-gui (see --tb)
TB=${TB:-tb_croc_soc}
VALID_TBS="tb_croc_soc tb_croc_chip"

mkdir -p reports

################
# Helpers
################

show_help() {
    cat << EOF
VSIM Coordinator

Usage:
    ./run_vsim.sh [OPTIONS]

Options:
    --help, -h          Show this help message
    --dry-run, -n       Only print commands instead of executing
    --verbose, -v       Print commands while executing
    --techfunctional    Bender targets for IHP13 tech cells and SRAM macros when regenerating
                        the file list with --flist (same as TECHFUNCTIONAL=1).
                        --build always compiles the tech cell, SRAM macro and IO pad models,
                        since compile_rtl.tcl needs them either way.
    --mbist-fault       Build with tc_sram_impl_fault.sv + the SRAM fault model instead of
                        tc_sram_impl_mod.sv (same as MBIST_FAULT=1). Faults are set in
                        rtl/SEM_PROJ_RTL/integrate_optimised_redundancy/mbist_fault_cfg_pkg.sv.
                        Only affects --build; rebuild without it to go back.
    --tb NAME           Testbench for --run / --run-gui (same as TB=NAME):
                          tb_croc_soc  (default) croc_soc directly
                          tb_croc_chip croc_chip with IO pads and boundary-scan TAP
                        Both are compiled by --build, so no rebuild is needed to switch.
    --plusarg +ARG      Extra simulator plusarg for --run / --run-gui (repeatable), e.g.
                        --plusarg +bscan_test    (boundary-scan test, tb_croc_chip + test_bscan.hex)
                        --plusarg +obi_jtag_test (OBI crossbar JTAG isolation test, tb_croc_chip)
    --flist             Regenerate compile script reading sources (compile_rtl.tcl, compile_netlist.tcl)
    --build             Compile Croc RTL in VSIM
    --build-netlist     Compile Croc post-synthesis netlist in VSIM
    --run BINARY        Run binary in VSIM
    --run-gui BINARY    Prepare running binary in VSIM, open GUI

Example:
    # Build and run RTL simulation with given binary (CLI mode)
    ./run_vsim.sh --build --run ../sw/bin/helloworld.hex

    # RTL simulation with IHP13 cells and SRAM macros
    ./run_vsim.sh --techfunctional --flist --build --run ../sw/bin/helloworld.hex

    # MBIST test with injected SRAM faults
    ./run_vsim.sh --techfunctional --mbist-fault --build --run ../sw/bin/test/test_mbist.hex

    # Same binary on the chip-level testbench
    ./run_vsim.sh --tb tb_croc_chip --run ../sw/bin/test/test_mbist.hex
EOF
    exit 0
}


run_cmd() {
    if [ "$DRYRUN" = 1 ]; then
        echo "$1"
    else
        eval "$1"
    fi
}


# Extra Bender targets for the RTL flow. 'techfunctional' becomes
# `ifdef TARGET_TECHFUNCTIONAL in the SystemVerilog sources.
rtl_extra_targets() {
    if [ "$TECHFUNCTIONAL" = 1 ]; then
        echo "-t techfunctional -t ihp13 -t tech_cells_generic_exclude_tc_clk -t tech_cells_generic_exclude_tc_sram"
    fi
}

# What QuestaSim sources at compile time. Tech models must come first.
rtl_compile_do() {
    # compile_rtl.tcl reads the Tcl variable MBIST_FAULT to pick the SRAM files. It always
    # instantiates IHP13 cells, SRAM macros and IO pads (tc_clk, tc_sram_impl_mod, croc_chip),
    # so their models (compile_tech_func.tcl) are compiled on every build, with or
    # without --techfunctional.
    echo "set TECHFUNCTIONAL ${TECHFUNCTIONAL}; set MBIST_FAULT ${MBIST_FAULT}; source compile_tech_func.tcl; source compile_rtl.tcl; exit"
}


# Abort if the compile log shows errors, or if the testbench (the last file
# compiled) never appeared, which means the compile script stopped early.
check_compile() {
    local log=$1 nerr=$2
    if [ "$DRYRUN" = 1 ]; then
        return 0
    fi
    if [ "$nerr" -gt 0 ]; then
        echo "[ERROR] ${nerr} compile error(s) in ${log}. First ones:" >&2
        grep -m5 "Error:" "${log}" >&2 || true
        exit 1
    fi
    if ! grep -q "tb_croc_soc" "${log}"; then
        echo "[ERROR] tb_croc_soc was never compiled, the compile script stopped early. End of ${log}:" >&2
        tail -n 15 "${log}" >&2
        exit 1
    fi
}


generate_rtl_flist() {
    run_cmd "echo [INFO][Bender] Generate compile_rtl.tcl TECHFUNCTIONAL=${TECHFUNCTIONAL}"
    run_cmd "bender \
        script vsim \
        -t rtl \
        $(rtl_extra_targets) \
        -t vsim \
        -t simulation \
        -t verilator \
        -DSYNTHESIS \
        -DSIMULATION \
        --vlog-arg=\"-svinputport=compat\" \
        > compile_rtl.tcl"

    run_cmd "echo [INFO][Bender] Remove absolute paths"
    run_cmd "sed -i 's|${CROC_ROOT}|..|g' compile_rtl.tcl"

    run_cmd "echo [INFO][Bender] File list generated: compile_rtl.tcl"
}


generate_netlist_flist() {
    run_cmd "echo [INFO][Bender] Generate compile_netlist.tcl"
    run_cmd "bender \
        script vsim \
        -t ihp13 \
        -t vsim \
        -t simulation \
        -t verilator \
        -t netlist_yosys \
        -DSYNTHESIS \
        -DSIMULATION \
        --vlog-arg=\"-svinputport=compat\" \
        > compile_netlist.tcl"

    run_cmd "echo [INFO][Bender] Remove absolute paths"
    run_cmd "sed -i 's|${CROC_ROOT}|..|g' compile_netlist.tcl"

    run_cmd "echo [INFO][Bender] File list generated: compile_netlist.tcl"
}


compile_rtl() {
    run_cmd "echo [INFO][VSIM] Compile TECHFUNCTIONAL=${TECHFUNCTIONAL} MBIST_FAULT=${MBIST_FAULT}"
    run_cmd "${VSIM} \
        -c \
        -do \"$(rtl_compile_do)\" \
        > reports/compile_rtl.log"

    # Collect errors and warnings from compilation log and print summary
    run_cmd "echo [INFO][VSIM] Check reports/compile_rtl.log"
    run_cmd "echo --- QuestaSim compilation report ---  > reports/compile_rtl.rpt"
    run_cmd "echo Errors:                              >> reports/compile_rtl.rpt"
    run_cmd "grep Error: reports/compile_rtl.log       >> reports/compile_rtl.rpt || true"
    run_cmd "echo                                      >> reports/compile_rtl.rpt"
    run_cmd "echo Warnings:                            >> reports/compile_rtl.rpt"
    run_cmd "grep Warning: reports/compile_rtl.log     >> reports/compile_rtl.rpt || true"

    run_cmd "NUM_ERRORS=$(cat reports/compile_rtl.rpt | grep Error: | wc -l)"
    run_cmd "NUM_WARNINGS=$(cat reports/compile_rtl.rpt | grep Warning: | wc -l)"
    run_cmd "echo \"#######################################################\""
    run_cmd "echo \"############### Compilation report ####################\""
    run_cmd "echo \"#######################################################\""
    run_cmd "echo  Errors   : ${NUM_ERRORS}"
    run_cmd "echo  Warnings : ${NUM_WARNINGS}"
    run_cmd "echo See 'reports/compile_rtl.rpt' for more info"
    run_cmd "echo \"#######################################################\""
    check_compile reports/compile_rtl.log "${NUM_ERRORS:-0}"
}


compile_netlist() {
    run_cmd "echo [INFO][VSIM] Compile post-synthesis netlist"
    run_cmd "${VSIM} \
        -c \
        -do \"source compile_netlist.tcl; source compile_tech.tcl; exit\" \
        > reports/compile_netlist.log"

    # Collect errors and warnings from compilation log and print summary
    run_cmd "echo [INFO][VSIM] Check reports/compile_netlist.log"
    run_cmd "echo --- QuestaSim compilation report ---  > reports/compile_netlist.rpt"
    run_cmd "echo Errors:                              >> reports/compile_netlist.rpt"
    run_cmd "grep Error: reports/compile_netlist.log       >> reports/compile_netlist.rpt || true"
    run_cmd "echo                                      >> reports/compile_netlist.rpt"
    run_cmd "echo Warnings:                            >> reports/compile_netlist.rpt"
    run_cmd "grep Warning: reports/compile_netlist.log     >> reports/compile_netlist.rpt || true"

    run_cmd "NUM_ERRORS=$(cat reports/compile_netlist.rpt | grep Error: | wc -l)"
    run_cmd "NUM_WARNINGS=$(cat reports/compile_netlist.rpt | grep Warning: | wc -l)"
    run_cmd "echo \"#######################################################\""
    run_cmd "echo \"############### Compilation report ####################\""
    run_cmd "echo \"#######################################################\""
    run_cmd "echo  Errors   : ${NUM_ERRORS}"
    run_cmd "echo  Warnings : ${NUM_WARNINGS}"
    run_cmd "echo See 'reports/compile_netlist.rpt' for more info"
    run_cmd "echo \"#######################################################\""
    check_compile reports/compile_netlist.log "${NUM_ERRORS:-0}"
}


# Classify vopt "missing port connection" warnings (vopt-2718) in a vsim log.
# The IO pad cells in croc_chip leave their power pins (iovdd/iovss/vdd/vss) unconnected on
# purpose (as upstream Croc; the pad ring connects them in layout), so those are expected.
# Any other missing port connection is listed as a real issue. The warnings themselves are
# not suppressed. vopt only prints them when it re-optimizes the design.
POWER_PINS="iovdd|iovss|vdd|vss"
check_port_connections() {
    local log=$1
    if [ "$DRYRUN" = 1 ]; then
        echo "check_port_connections ${log}"
        return 0
    fi
    local all power other
    all=$(grep "vopt-2718.*Missing connection for port" "${log}" || true)
    if [ -z "${all}" ]; then
        echo "[INFO][VSIM] Port check: no missing port connections reported (or design not re-optimized)"
        return 0
    fi
    power=$(echo "${all}" | grep -E -c "port '(${POWER_PINS})'" || true)
    other=$(echo "${all}" | grep -E -v "port '(${POWER_PINS})'" || true)
    echo "#######################################################"
    echo "[INFO][VSIM] Port check: ${power} missing power-pin connection(s) (${POWER_PINS//|/, }): expected, ignored"
    if [ -n "${other}" ]; then
        echo "[WARNING][VSIM] Port check: $(echo "${other}" | wc -l) missing NON-power port connection(s):" >&2
        echo "${other}" | sed 's/^# \*\* Warning: /    /' >&2
    else
        echo "[INFO][VSIM] Port check: no missing non-power port connections"
    fi
    echo "#######################################################"
}


run_vsim() {
    run_cmd "${VSIM} \
        +binary=$1 \
        ${PLUSARGS} \
        -c \
        ${TB} \
        -t 1ns \
        -suppress vsim-3009 \
        -suppress vsim-8683 \
        -suppress vsim-8386 \
        -do \"run -a; quit\" \
        2>&1 | tee reports/run_vsim.log"
    check_port_connections reports/run_vsim.log
}


run_vsim_gui() {
    run_cmd "${VSIM} \
        +binary=$1 \
        ${PLUSARGS} \
        -gui \
        ${TB} \
        -t 1ns \
        -voptargs=+acc \
        -suppress vsim-3009 \
        -suppress vsim-8683 \
        -suppress vsim-8386"
}


####################
# Parse Arguments
####################

DRYRUN=0

# default action if no argument is given
if [ $# -eq 0 ]; then
    show_help
fi

# check for global arguments (must be handled before any action runs)
for arg in "$@"; do
    [[ "$arg" == -v || "$arg" == --verbose ]] && set -x
    [[ "$arg" == -n || "$arg" == --dry-run ]] && DRYRUN=1
    [[ "$arg" == --techfunctional ]] && TECHFUNCTIONAL=1
    [[ "$arg" == --mbist-fault ]] && MBIST_FAULT=1
done

# --tb and --plusarg take a value, so scan for them by index
PLUSARGS=""
args=("$@")
for ((i = 0; i < ${#args[@]}; i++)); do
    [[ "${args[i]}" == --tb ]] && TB="${args[i+1]:-}"
    if [[ "${args[i]}" == --plusarg ]]; then
        if [[ "${args[i+1]:-}" != +* ]]; then
            echo "[ERROR] --plusarg needs a value starting with '+' (e.g. --plusarg +bscan_test)" >&2
            exit 1
        fi
        PLUSARGS="${PLUSARGS} ${args[i+1]}"
    fi
done
if [[ " ${VALID_TBS} " != *" ${TB} "* ]]; then
    echo "[ERROR] Unknown testbench '${TB}' (valid: ${VALID_TBS})" >&2
    exit 1
fi

# parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --help|-h)
            show_help
            ;;
        --verbose|-v)
            shift
            ;;
        --dry-run|-n)
            shift
            ;;
        --techfunctional)
            shift
            ;;
        --mbist-fault)
            shift
            ;;
        --tb|--plusarg)
            shift 2
            ;;
        # script-specific commands
        --flist)
            generate_rtl_flist
            generate_netlist_flist
            shift
            ;;
        --build)
            compile_rtl
            shift
            ;;
        --build-netlist)
            compile_netlist
            shift
            ;;
        --run)
            run_vsim $2
            shift 2
            ;;
        --run-gui)
            run_vsim_gui $2
            shift 2
            ;;
        # Error handling
        *)
            echo "[ERROR] Unknown option: $1 (use --help for usage)" >&2
            exit 1
            ;;
    esac
done
























# #!/bin/bash
# # Copyright (c) 2026 ETH Zurich and University of Bologna.
# # Licensed under the Apache License, Version 2.0, see LICENSE for details.
# # SPDX-License-Identifier: Apache-2.0
# #
# # Published with permission from Siemens.
# # Siemens QuestaSim is available through EDA Higher Education Software Program
# # https://www.sw.siemens.com/en-US/academic/educators/eda-higher-education-software/
# #
# # Authors:
# # - Thomas Benz     <tbenz@iis.ee.ethz.ch>
# #
# # Modified: TECHFUNCTIONAL switch (IHP13 tech cells + SRAM macro models in RTL sim)


# set -e  # Exit on error
# set -u  # Error on undefined vars


# ################
# # Setup
# ################
# # Source environment
# source "../env.sh"

# VSIM=${VSIM:-questa-2023.4 vsim}

# # 1 = RTL simulation with IHP13 cells and SRAM macro models (see --techfunctional)
# TECHFUNCTIONAL=${TECHFUNCTIONAL:-0}

# mkdir -p reports

# ################
# # Helpers
# ################

# show_help() {
#     cat << EOF
# VSIM Coordinator

# Usage:
#     ./run_vsim.sh [OPTIONS]

# Options:
#     --help, -h          Show this help message
#     --dry-run, -n       Only print commands instead of executing
#     --verbose, -v       Print commands while executing
#     --techfunctional    Use IHP13 tech cells and SRAM macro models in RTL sim
#                         (same as TECHFUNCTIONAL=1). Default: generic tech cells.
#                         Use the same setting for --flist and --build.
#     --flist             Regenerate compile script reading sources (compile_rtl.tcl, compile_netlist.tcl)
#     --build             Compile Croc RTL in VSIM
#     --build-netlist     Compile Croc post-synthesis netlist in VSIM
#     --run BINARY        Run binary in VSIM
#     --run-gui BINARY    Prepare running binary in VSIM, open GUI

# Example:
#     # Build and run RTL simulation with given binary (CLI mode)
#     ./run_vsim.sh --build --run ../sw/bin/helloworld.hex

#     # RTL simulation with IHP13 cells and SRAM macros
#     ./run_vsim.sh --techfunctional --flist --build --run ../sw/bin/helloworld.hex
# EOF
#     exit 0
# }


# run_cmd() {
#     if [ "$DRYRUN" = 1 ]; then
#         echo "$1"
#     else
#         eval "$1"
#     fi
# }


# # Extra Bender targets for the RTL flow. 'techfunctional' becomes
# # `ifdef TARGET_TECHFUNCTIONAL in the SystemVerilog sources.
# rtl_extra_targets() {
#     if [ "$TECHFUNCTIONAL" = 1 ]; then
#         echo "-t techfunctional -t ihp13 -t tech_cells_generic_exclude_tc_clk -t tech_cells_generic_exclude_tc_sram"
#     fi
# }

# # What QuestaSim sources at compile time. Tech models must come first.
# rtl_compile_do() {
#     if [ "$TECHFUNCTIONAL" = 1 ]; then
#         echo "source compile_tech_func.tcl; source compile_rtl.tcl; exit"
#     else
#         echo "source compile_rtl.tcl; exit"
#     fi
# }


# generate_rtl_flist() {
#     run_cmd "echo [INFO][Bender] Generate compile_rtl.tcl TECHFUNCTIONAL=${TECHFUNCTIONAL}"
#     run_cmd "bender \
#         script vsim \
#         -t rtl \
#         $(rtl_extra_targets) \
#         -t vsim \
#         -t simulation \
#         -t verilator \
#         -DSYNTHESIS \
#         -DSIMULATION \
#         --vlog-arg=\"-svinputport=compat\" \
#         > compile_rtl.tcl"

#     run_cmd "echo [INFO][Bender] Remove absolute paths"
#     run_cmd "sed -i 's|${CROC_ROOT}|..|g' compile_rtl.tcl"

#     run_cmd "echo [INFO][Bender] File list generated: compile_rtl.tcl"
# }


# generate_netlist_flist() {
#     run_cmd "echo [INFO][Bender] Generate compile_netlist.tcl"
#     run_cmd "bender \
#         script vsim \
#         -t ihp13 \
#         -t vsim \
#         -t simulation \
#         -t verilator \
#         -t netlist_yosys \
#         -DSYNTHESIS \
#         -DSIMULATION \
#         --vlog-arg=\"-svinputport=compat\" \
#         > compile_netlist.tcl"

#     run_cmd "echo [INFO][Bender] Remove absolute paths"
#     run_cmd "sed -i 's|${CROC_ROOT}|..|g' compile_netlist.tcl"

#     run_cmd "echo [INFO][Bender] File list generated: compile_netlist.tcl"
# }


# compile_rtl() {
#     run_cmd "echo [INFO][VSIM] Compile TECHFUNCTIONAL=${TECHFUNCTIONAL}"
#     run_cmd "${VSIM} \
#         -c \
#         -do \"$(rtl_compile_do)\" \
#         > reports/compile_rtl.log"

#     # Collect errors and warnings from compilation log and print summary
#     run_cmd "echo [INFO][VSIM] Check reports/compile_rtl.log"
#     run_cmd "echo --- QuestaSim compilation report ---  > reports/compile_rtl.rpt"
#     run_cmd "echo Errors:                              >> reports/compile_rtl.rpt"
#     run_cmd "grep Error: reports/compile_rtl.log       >> reports/compile_rtl.rpt || true"
#     run_cmd "echo                                      >> reports/compile_rtl.rpt"
#     run_cmd "echo Warnings:                            >> reports/compile_rtl.rpt"
#     run_cmd "grep Warning: reports/compile_rtl.log     >> reports/compile_rtl.rpt || true"

#     run_cmd "NUM_ERRORS=$(cat reports/compile_rtl.rpt | grep Error: | wc -l)"
#     run_cmd "NUM_WARNINGS=$(cat reports/compile_rtl.rpt | grep Warning: | wc -l)"
#     run_cmd "echo \"#######################################################\""
#     run_cmd "echo \"############### Compilation report ####################\""
#     run_cmd "echo \"#######################################################\""
#     run_cmd "echo  Errors   : ${NUM_ERRORS}"
#     run_cmd "echo  Warnings : ${NUM_WARNINGS}"
#     run_cmd "echo See 'reports/compile_rtl.rpt' for more info"
#     run_cmd "echo \"#######################################################\""
# }


# compile_netlist() {
#     run_cmd "echo [INFO][VSIM] Compile post-synthesis netlist"
#     run_cmd "${VSIM} \
#         -c \
#         -do \"source compile_netlist.tcl; source compile_tech.tcl; exit\" \
#         > reports/compile_netlist.log"

#     # Collect errors and warnings from compilation log and print summary
#     run_cmd "echo [INFO][VSIM] Check reports/compile_netlist.log"
#     run_cmd "echo --- QuestaSim compilation report ---  > reports/compile_netlist.rpt"
#     run_cmd "echo Errors:                              >> reports/compile_netlist.rpt"
#     run_cmd "grep Error: reports/compile_netlist.log       >> reports/compile_netlist.rpt || true"
#     run_cmd "echo                                      >> reports/compile_netlist.rpt"
#     run_cmd "echo Warnings:                            >> reports/compile_netlist.rpt"
#     run_cmd "grep Warning: reports/compile_netlist.log     >> reports/compile_netlist.rpt || true"

#     run_cmd "NUM_ERRORS=$(cat reports/compile_netlist.rpt | grep Error: | wc -l)"
#     run_cmd "NUM_WARNINGS=$(cat reports/compile_netlist.rpt | grep Warning: | wc -l)"
#     run_cmd "echo \"#######################################################\""
#     run_cmd "echo \"############### Compilation report ####################\""
#     run_cmd "echo \"#######################################################\""
#     run_cmd "echo  Errors   : ${NUM_ERRORS}"
#     run_cmd "echo  Warnings : ${NUM_WARNINGS}"
#     run_cmd "echo See 'reports/compile_netlist.rpt' for more info"
#     run_cmd "echo \"#######################################################\""
# }


# run_vsim() {
#     run_cmd "${VSIM} \
#         +binary=$1 \
#         -c \
#         tb_croc_soc \
#         -t 1ns \
#         -suppress vsim-3009 \
#         -suppress vsim-8683 \
#         -suppress vsim-8386 \
#         -do \"run -a; quit\""
# }


# run_vsim_gui() {
#     run_cmd "${VSIM} \
#         +binary=$1 \
#         -gui \
#         tb_croc_soc \
#         -t 1ns \
#         -voptargs=+acc \
#         -suppress vsim-3009 \
#         -suppress vsim-8683 \
#         -suppress vsim-8386"
# }


# ####################
# # Parse Arguments
# ####################

# DRYRUN=0

# # default action if no argument is given
# if [ $# -eq 0 ]; then
#     show_help
# fi

# # check for global arguments (must be handled before any action runs)
# for arg in "$@"; do
#     [[ "$arg" == -v || "$arg" == --verbose ]] && set -x
#     [[ "$arg" == -n || "$arg" == --dry-run ]] && DRYRUN=1
#     [[ "$arg" == --techfunctional ]] && TECHFUNCTIONAL=1
# done

# # parse arguments
# while [[ $# -gt 0 ]]; do
#     case "$1" in
#         --help|-h)
#             show_help
#             ;;
#         --verbose|-v)
#             shift
#             ;;
#         --dry-run|-n)
#             shift
#             ;;
#         --techfunctional)
#             shift
#             ;;
#         # script-specific commands
#         --flist)
#             generate_rtl_flist
#             generate_netlist_flist
#             shift
#             ;;
#         --build)
#             compile_rtl
#             shift
#             ;;
#         --build-netlist)
#             compile_netlist
#             shift
#             ;;
#         --run)
#             run_vsim $2
#             shift 2
#             ;;
#         --run-gui)
#             run_vsim_gui $2
#             shift 2
#             ;;
#         # Error handling
#         *)
#             echo "[ERROR] Unknown option: $1 (use --help for usage)" >&2
#             exit 1
#             ;;
#     esac
# done