#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include "hal.h"

/* ------------------------------------------------------------------ */
/* HAL stubs — in real HW these map to register-level calls            */
/* ------------------------------------------------------------------ */

void hal_init(void)
{
    /* Simulate peripheral clock enable, MPU config, etc. */
    printf("[HAL] System initialized\n");
}

void hal_delay_ms(uint32_t ms)
{
    /*
     * On real HW: SysTick-based busy loop or sleep.
     * In simulation we skip the actual wait.
     */
    (void)ms;
}

void hal_enter_low_power(void)
{
    printf("[HAL] Entering low-power mode (WFI)\n");
}

void uart_init(uint32_t baudrate)
{
    (void)baudrate;
    /* UART peripheral already routed to stdout in QEMU */
}

void uart_print(const char *str)
{
    printf("%s", str);
}

void uart_print_uint(uint32_t value)
{
    printf("%u", value);
}

void led_set(led_id_t led, led_state_t state)
{
    const char *names[] = { "STATUS", "ERROR" };
    printf("[HAL] LED %s -> %s\n", names[led], state ? "ON" : "OFF");
}
