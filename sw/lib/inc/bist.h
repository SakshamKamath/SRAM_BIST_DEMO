

#pragma once
#include <stdint.h>
// #include <stdio.h>
#include "config.h"
#include "uart.h"
#include "print.h"
#include "util.h"

// #define MBIST_TEST_BASE_ADDRESS SOCCTRL_BASE_ADDR // Same as PeriphSocCtrl --> Check croc_pkg.sv
#define MBIST_TEST_BASE_ADDRESS 0x03000000 // Same as PeriphSocCtrl --> Check croc_pkg.sv

#define MBIST_START_OFFSET             0x40 // Check soc_ctrl_regs_pkg.sv
#define MBIST_RESUME_OR_RESET_OFFSET   0x44 // Check soc_ctrl_regs_pkg.sv
#define MBIST_ERRADDR_READ_OFFSET      0x48 // Check soc_ctrl_regs_pkg.sv
#define MBIST_STATUS_READ_OFFSET0      0x4C // Check soc_ctrl_regs_pkg.sv
#define MBIST_ERRADDR_FIFO_OFFSET0     0x50 // Check soc_ctrl_regs_pkg.sv (macro i at 0x50 + 4*i)

/* Readme:
MBIST_START_OFFSET --> Triggers mbist start
MBIST_RESUME_OR_RESET_OFFSET --> Triggers either reset or resumption of mbist after fifo full of failures
MBIST_ERRADDR_READ_OFFSET  --> Write: pops (discards) one error FIFO entry per macro bit set
MBIST_STATUS_READ_OFFSET0  --> Read only register where the status of all macro mbist present (4bits per macro so 8 macros supported)
MBIST_ERRADDR_FIFO_OFFSET0 --> Read only, one word per macro: {valid[31], 0, word address within the bank}.
                               Every read pops one entry of that macro's error FIFO.

MBIST is destructive: the tested bank is left all zeros. Macro i is SRAM bank i, so
software can only test macro 1 (data SRAM) while it runs from bank 0. Macro 0 must be
tested over JTAG.

Macros 2 and 3 are the VAD frame SRAMs (512x32, bank 0 and bank 1) in the user domain.
They are not on the system bus: for them, error addresses are word indices (0..511).
Hold the VAD in debug mode (SRAM_CTRL.DBG_EN) while testing them, so no audio or VAD
access happens during the march.
*/

#define MBIST_NUM_SRAM_BANKS 2  // croc_pkg::NumSramBanks
#define MBIST_NUM_MACROS    4   // + user_pkg::NumUserMbistMacros (VAD frame SRAMs)
#define MBIST_MACRO_VAD_BANK0 2
#define MBIST_MACRO_VAD_BANK1 3

// SRAM layout used to turn a FIFO word address into a byte address (croc_pkg.sv)
#define MBIST_SRAM_BASE_ADDR    0x10000000
#define MBIST_BANK_BYTES        0x800       // SramBankNumWords (512) * 4

#define MBIST_ERRADDR_VALID     (1u << 31)
#define MBIST_ERRADDR_WORD_MASK 0x1FF       // $clog2(SramBankNumWords) = 9 bits

// Per-macro status nibble in MBIST_STATUS_READ_OFFSET0: {pause, fail, busy, done}
#define MBIST_STATUS_DONE   0x1
#define MBIST_STATUS_BUSY   0x2
#define MBIST_STATUS_FAIL   0x4   // error FIFO not empty
#define MBIST_STATUS_PAUSE  0x8   // error FIFO full, controller waiting in St_RepairWait

// Error-address FIFO entries per macro: 2**FifoDepth, FifoDepth = 2 in croc_domain.sv
#define MBIST_ERR_FIFO_DEPTH 4

#define MBIST_OK              0
#define MBIST_ERR_TIMEOUT    (-1)
#define MBIST_ERR_BAD_MACRO  (-2)
#define MBIST_ERR_FAIL       (-3)


// Function Declarations

// Pops one entry of the macro's error FIFO. Returns 1 and the failing byte address in
// *byte_addr if there was one, 0 if the FIFO was empty. For the VAD macros (2, 3) the
// returned value is the word index within the frame SRAM instead.
int mbist_pop_erraddr(uint32_t macro, uint32_t *byte_addr);

// Runs MBIST on one macro. Failing byte addresses are stored in err_addrs (up to
// max_errs of them; pass NULL/0 to discard). *num_errs (if not NULL) gets the total
// number of FIFO entries read, which can exceed max_errs.
int32_t mbist_run_macro(uint32_t macro, uint32_t *err_addrs, uint32_t max_errs,
                        uint32_t *num_errs);
