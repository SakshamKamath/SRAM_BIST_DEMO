#include "bist.h"

#define MAX_ERRS 16

int main(void)
{
    uart_init();
    printf("Starting MBIST\n");

    // Macro 1 = data SRAM (bank 1). This program and its stack live in bank 0.
    uint32_t err_addrs[MAX_ERRS];
    uint32_t num_errs;
    int32_t ret = mbist_run_macro(1, err_addrs, MAX_ERRS, &num_errs);

    printf("MBIST finished: %x, errors: %x\n", (uint32_t)ret, num_errs);
    for (uint32_t i = 0; i < num_errs && i < MAX_ERRS; i++)
        printf("  fail @ %x\n", err_addrs[i]);
    uart_write_flush();


    return ret;
}
