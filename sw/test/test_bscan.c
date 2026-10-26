// Core side of the boundary-scan test in tb_croc_chip. Run with
//   ./run_vsim.sh --tb tb_croc_chip --plusarg +bscan_test --run ../sw/bin/test/test_bscan.hex
//
// GPIO[15:8] are outputs, GPIO[31:16] inputs. The testbench drives and observes the pins
// and the boundary-scan register (BSR) over JTAG:
//   1. Drive BSCAN_READY on GPIO[15:8]   -> TB checks the pins and the BSR (SAMPLE)
//   2. Wait for BSCAN_GO on GPIO[31:24]
//   3. Echo GPIO[23:16] to GPIO[15:8] until BSCAN_DONE on GPIO[31:24]
//      -> under INTEST the core inputs come from the BSR, so the echo shows the BSR
//         pattern instead of the pin values

#include "gpio.h"

#define BSCAN_READY   0xA5
#define BSCAN_GO      0x5A
#define BSCAN_DONE    0xC3
#define BSCAN_TIMEOUT 100000   // loop iterations before giving up

static uint32_t gpio_in_byte(int byte)
{
    return (gpio_read() >> (8 * byte)) & 0xFF;
}

int main(void)
{
    uint32_t n;

    gpio_set_direction(0xFFFFFF00, 0x0000FF00);
    gpio_enable(0xFFFFFF00);
    gpio_write(BSCAN_READY << 8);

    for (n = 0; gpio_in_byte(3) != BSCAN_GO; n++)
        if (n > BSCAN_TIMEOUT)
            return 1;

    for (n = 0; gpio_in_byte(3) != BSCAN_DONE; n++) {
        gpio_write(gpio_in_byte(2) << 8);
        if (n > BSCAN_TIMEOUT)
            return 2;
    }

    gpio_disable(0xFFFFFF00);
    return 0;
}
