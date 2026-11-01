// VAD interrupt path, triggered from software (SRAM_CMD.IRQ_TRIG), no audio needed.
// Checks the interrupt at three points: the VAD's own read-back (SRAM_STATUS.IRQ), the
// core's pending bit (mip) and the handler running, then the acknowledge (W1C).

#include "util.h"
#include "config.h"

#define VAD_BASE         0x20000000  // croc_pkg::UserBaseAddr, user_pkg UserDesign
#define VAD_SRAM_CTRL    0x2C
#define VAD_SRAM_CMD     0x38
#define VAD_SRAM_STATUS  0x40
#define VAD_CTRL_IRQ_EN  0x8
#define VAD_CMD_IRQ_TRIG 0x10
#define VAD_STAT_SPEECH  0x1
#define VAD_STAT_IRQ     (1u << 13)

#define IRQ_VAD          20          // user interrupt 0 = fast interrupt 4

#define VAD_REG(off) (*(volatile uint32_t *)(VAD_BASE + (off)))

static volatile int      irq_count = 0;
static volatile uint32_t irq_cause = 0;
static volatile uint32_t irq_status = 0;

static inline uint32_t get_mip(void)
{
    uint32_t mip;
    asm volatile("csrr %0, mip" : "=r"(mip)::"memory");
    return mip;
}

// Overrides the weak default handler; the bootrom trap handler dispatches here.
void croc_interrupt_handler(uint32_t cause)
{
    irq_cause = cause;
    if (cause == IRQ_VAD) {
        irq_status = VAD_REG(VAD_SRAM_STATUS);
        VAD_REG(VAD_SRAM_STATUS) = VAD_STAT_SPEECH;  // acknowledge: W1C drops the line
        irq_count++;
    }
}

int main(void)
{
    uint32_t st;

    // 1) Trigger with the VAD interrupt disabled: flag set, line low everywhere
    VAD_REG(VAD_SRAM_CTRL)   = 0;
    VAD_REG(VAD_SRAM_STATUS) = VAD_STAT_SPEECH;
    VAD_REG(VAD_SRAM_CMD)    = VAD_CMD_IRQ_TRIG;
    st = VAD_REG(VAD_SRAM_STATUS);
    CHECK_ASSERT(1, (st & VAD_STAT_SPEECH) && !(st & VAD_STAT_IRQ));
    CHECK_ASSERT(2, !(get_mip() & (1u << IRQ_VAD)));

    // 2) Enable it in the VAD, core interrupts still off: line high, pending in the core
    VAD_REG(VAD_SRAM_CTRL) = VAD_CTRL_IRQ_EN;
    st = VAD_REG(VAD_SRAM_STATUS);
    CHECK_ASSERT(3, st & VAD_STAT_IRQ);
    CHECK_ASSERT(4, get_mip() & (1u << IRQ_VAD));

    // 3) Enable it in the core: the handler runs once and acknowledges
    set_interrupt_enable(1, IRQ_VAD);
    set_global_irq_enable(1);
    for (volatile int i = 0; i < 1000 && irq_count == 0; i++)
        ;
    CHECK_ASSERT(5, irq_count == 1);
    CHECK_ASSERT(6, irq_cause == IRQ_VAD);
    CHECK_ASSERT(7, (irq_status & VAD_STAT_SPEECH) && (irq_status & VAD_STAT_IRQ));
    st = VAD_REG(VAD_SRAM_STATUS);
    CHECK_ASSERT(8, !(st & (VAD_STAT_SPEECH | VAD_STAT_IRQ)));
    CHECK_ASSERT(9, !(get_mip() & (1u << IRQ_VAD)));

    // 4) Trigger again with everything enabled: taken straight away, exactly once more
    VAD_REG(VAD_SRAM_CMD) = VAD_CMD_IRQ_TRIG;
    for (volatile int i = 0; i < 1000 && irq_count < 2; i++)
        ;
    CHECK_ASSERT(10, irq_count == 2);
    for (volatile int i = 0; i < 100; i++)
        ;
    CHECK_ASSERT(11, irq_count == 2);

    // 5) Masked in the VAD: a trigger sets the flag but does not interrupt
    VAD_REG(VAD_SRAM_CTRL) = 0;
    VAD_REG(VAD_SRAM_CMD)  = VAD_CMD_IRQ_TRIG;
    for (volatile int i = 0; i < 100; i++)
        ;
    CHECK_ASSERT(12, irq_count == 2);
    CHECK_ASSERT(13, VAD_REG(VAD_SRAM_STATUS) & VAD_STAT_SPEECH);
    VAD_REG(VAD_SRAM_STATUS) = VAD_STAT_SPEECH;

    set_interrupt_enable(0, IRQ_VAD);
    set_global_irq_enable(0);
    return 0;
}
