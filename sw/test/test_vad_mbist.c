// MBIST of the VAD frame SRAMs (MBIST macros 2 and 3) through soc_ctrl_regs.
// Checks: both banks pass, the croc SRAM banks are not started (this program lives in
// bank 0), and the VAD banks are all zeros afterwards (read via the VAD debug registers).

#include "bist.h"

#define VAD_BASE        0x20000000  // croc_pkg::UserBaseAddr, user_pkg UserDesign
#define VAD_SRAM_CTRL   0x2C
#define VAD_SRAM_ADDR   0x30
#define VAD_SRAM_WDATA  0x34
#define VAD_SRAM_CMD    0x38
#define VAD_SRAM_RDATA  0x3C
#define VAD_CTRL_DBG_EN 0x1
#define VAD_CTRL_BANK1  0x2
#define VAD_CMD_WRITE   0x1
#define VAD_CMD_READ    0x2

#define VAD_REG(off) (*(volatile uint32_t *)(VAD_BASE + (off)))

static uint32_t vad_read(uint32_t bank, uint32_t addr)
{
    VAD_REG(VAD_SRAM_CTRL) = VAD_CTRL_DBG_EN | (bank ? VAD_CTRL_BANK1 : 0);
    VAD_REG(VAD_SRAM_ADDR) = addr;
    VAD_REG(VAD_SRAM_CMD)  = VAD_CMD_READ;
    return VAD_REG(VAD_SRAM_RDATA);
}

static void vad_write(uint32_t bank, uint32_t addr, uint32_t data)
{
    VAD_REG(VAD_SRAM_CTRL)  = VAD_CTRL_DBG_EN | (bank ? VAD_CTRL_BANK1 : 0);
    VAD_REG(VAD_SRAM_ADDR)  = addr;
    VAD_REG(VAD_SRAM_WDATA) = data;
    VAD_REG(VAD_SRAM_CMD)   = VAD_CMD_WRITE;
}

int main(void)
{
    uart_init();
    printf("Starting VAD MBIST\n");

    // Fill both banks with a pattern so the march has to overwrite real data
    for (uint32_t bank = 0; bank < 2; bank++)
        for (uint32_t addr = 0; addr < 512; addr += 37)
            vad_write(bank, addr, 0xA5A5 ^ addr);
    CHECK_ASSERT(1, vad_read(1, 37) == (0xA5A5 ^ 37));

    for (uint32_t bank = 0; bank < 2; bank++) {
        uint32_t num_errs;
        int32_t ret = mbist_run_macro(MBIST_MACRO_VAD_BANK0 + bank, 0, 0, &num_errs);
        printf("VAD bank %x MBIST: %x, errors: %x\n", bank, (uint32_t)ret, num_errs);
        CHECK_ASSERT(10 + bank, ret == MBIST_OK && num_errs == 0);

        // March leaves the bank all zeros
        for (uint32_t addr = 0; addr < 512; addr += 37)
            CHECK_ASSERT(20 + bank, vad_read(bank, addr) == 0);
    }

    // Croc SRAM banks were never started
    uint32_t status = *(volatile uint32_t *)(MBIST_TEST_BASE_ADDRESS + MBIST_STATUS_READ_OFFSET0);
    CHECK_ASSERT(30, (status & 0xFF) == 0);

    // Functional VAD SRAM access still works
    vad_write(0, 100, 0x1234);
    CHECK_ASSERT(31, vad_read(0, 100) == 0x1234);
    VAD_REG(VAD_SRAM_CTRL) = 0;

    printf("VAD MBIST done\n");
    uart_write_flush();
    return 0;
}
