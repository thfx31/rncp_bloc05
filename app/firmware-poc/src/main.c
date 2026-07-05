/**
 * firmware-poc - Fictional embedded firmware for POC demonstration
 * Target: ARM Cortex-M (QEMU virt)
 *
 * Simulates a minimal satellite subsystem:
 *   - Telemetry acquisition loop
 *   - LED status indicator
 *   - UART output
 */

#include <stdint.h>
#include <stdio.h>
#include "hal.h"
#include "telemetry.h"

#define FIRMWARE_VERSION    "1.0.0"
#define TELEMETRY_INTERVAL_MS  1000
#define MAX_ITERATIONS          10

static volatile uint32_t system_tick = 0;

/**
 * @brief System tick increment (simulates SysTick ISR)
 */
void systick_handler(void)
{
    system_tick++;
}

/**
 * @brief Main firmware entry point
 */
int main(void)
{
    hal_init();
    uart_init(115200);
    telemetry_init();

    uart_print("=== POC Firmware v" FIRMWARE_VERSION " ===\r\n");
    uart_print("Target: ARM Cortex-M / QEMU\r\n");
    uart_print("Subsystem: Telemetry Acquisition\r\n\r\n");

    led_set(LED_STATUS, LED_ON);

    for (uint32_t i = 0; i < MAX_ITERATIONS; i++) {
        telemetry_data_t data;

        telemetry_acquire(&data);

        if (telemetry_validate(&data) != TELEMETRY_OK) {
            uart_print("[ERROR] Telemetry validation failed\r\n");
            led_set(LED_ERROR, LED_ON);
            continue;
        }

        telemetry_send(&data);

        uart_print("[INFO] Telemetry frame sent - iteration: ");
        uart_print_uint(i + 1);
        uart_print("\r\n");

        hal_delay_ms(TELEMETRY_INTERVAL_MS);
    }

    uart_print("\r\n[INFO] Acquisition loop complete. Entering low-power mode.\r\n");
    led_set(LED_STATUS, LED_OFF);

    hal_enter_low_power();

    /* Should not reach here */
    while (1) {}

    return 0;
}
