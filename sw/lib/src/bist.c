#include <stdint.h>
#include "bist.h"

// Memory-mapped 32-bit register access. volatile forces a real bus access every time.
#define MBIST_REG(offset) (*(volatile uint32_t *)(uintptr_t)(MBIST_TEST_BASE_ADDRESS + (offset)))

#define MBIST_STATUS_BITS_PER_MACRO 4
#define MBIST_MACROS_PER_STATUS_REG (32 / MBIST_STATUS_BITS_PER_MACRO)   // 8
#define MBIST_STATUS_FIELD_MASK     0xF   // one macro's 4-bit status field (before shifting)

// Byte distance between consecutive status registers. ASSUMPTION: contiguous 32-bit
// registers. Override from bist.h or the build if the spec says otherwise.
#ifndef MBIST_STATUS_REG_STRIDE
#define MBIST_STATUS_REG_STRIDE     4
#endif

// A march on one 512x32 bank takes ~10k cycles; each poll is several cycles.
#define MBIST_POLL_TIMEOUT          100000

int mbist_pop_erraddr(uint32_t macro, uint32_t *byte_addr)
{
    // Reading the window pops the FIFO; a read of an empty FIFO returns valid = 0.
    uint32_t v = MBIST_REG(MBIST_ERRADDR_FIFO_OFFSET0 + 4 * macro);
    if (!(v & MBIST_ERRADDR_VALID))
        return 0;
    if (macro >= MBIST_NUM_SRAM_BANKS)   // VAD frame SRAM: not on the bus, word index
        *byte_addr = v & MBIST_ERRADDR_WORD_MASK;
    else
        *byte_addr = MBIST_SRAM_BASE_ADDR + macro * MBIST_BANK_BYTES +
                     (v & MBIST_ERRADDR_WORD_MASK) * 4;
    return 1;
}

// Reads out every entry of the macro's error FIFO (at most MBIST_ERR_FIFO_DEPTH).
static void mbist_drain_err_fifo(uint32_t macro, uint32_t *err_addrs, uint32_t max_errs,
                                 uint32_t *count)
{
    uint32_t addr;
    for (uint32_t i = 0; i < MBIST_ERR_FIFO_DEPTH; i++) {
        if (!mbist_pop_erraddr(macro, &addr))
            break;
        if (err_addrs && *count < max_errs)
            err_addrs[*count] = addr;
        (*count)++;
    }
}

// Runs MBIST on one macro (0 .. MBIST_NUM_MACROS-1). The tested bank is left all zeros,
// so no code, data or stack may live in it.
int32_t mbist_run_macro(uint32_t macro, uint32_t *err_addrs, uint32_t max_errs,
                        uint32_t *num_errs)
{
    if (macro >= MBIST_NUM_MACROS)
        return MBIST_ERR_BAD_MACRO;

    const uint32_t start_bit    = 1u << macro;                                 // bit n -> macro n
    const uint32_t status_off   = MBIST_STATUS_READ_OFFSET0 +
                                  (macro / MBIST_MACROS_PER_STATUS_REG) * MBIST_STATUS_REG_STRIDE;
    const uint32_t status_shift = (macro % MBIST_MACROS_PER_STATUS_REG) * MBIST_STATUS_BITS_PER_MACRO;

    // Trigger MBIST for this macro. Plain write (not read-modify-write): the start
    // register is a trigger, so we don't want to re-write stale bits for other macros.
    MBIST_REG(MBIST_START_OFFSET) = start_bit;

    // Poll only the done bit: with failures logged the field reads 0x5, not 0x1.
    // The fail bit only means "FIFO not empty", so draining clears it: remember it here.
    uint32_t field;
    uint32_t failed = 0;
    uint32_t polls  = 0;
    uint32_t count  = 0;
    if (num_errs)
        *num_errs = 0;
    do {
        field = (MBIST_REG(status_off) >> status_shift) & MBIST_STATUS_FIELD_MASK;

        if (field & MBIST_STATUS_PAUSE) {
            // Error FIFO full: read it out, then let the march continue from the next address.
            failed = 1;
            mbist_drain_err_fifo(macro, err_addrs, max_errs, &count);
            MBIST_REG(MBIST_RESUME_OR_RESET_OFFSET) = start_bit;

            // Status is registered twice: wait until it shows the controller left the pause,
            // otherwise a stale pause could resume a finished run from St_Done back to St_Idle.
            do {
                field = (MBIST_REG(status_off) >> status_shift) & MBIST_STATUS_FIELD_MASK;
                if (++polls > MBIST_POLL_TIMEOUT)
                    return MBIST_ERR_TIMEOUT;
            } while (field & MBIST_STATUS_PAUSE);
        }

        if (++polls > MBIST_POLL_TIMEOUT)
            return MBIST_ERR_TIMEOUT;
    } while (!(field & MBIST_STATUS_DONE));

    if (field & MBIST_STATUS_FAIL)
        failed = 1;

    // Read out the remaining entries (also needed because a new start does not clear the FIFO).
    mbist_drain_err_fifo(macro, err_addrs, max_errs, &count);
    if (num_errs)
        *num_errs = count;

    // Move the controller St_Done -> St_Idle so a later start is accepted.
    MBIST_REG(MBIST_RESUME_OR_RESET_OFFSET) = start_bit;

    return failed ? MBIST_ERR_FAIL : MBIST_OK;
}
