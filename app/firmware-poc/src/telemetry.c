#include <stdint.h>
#include <string.h>
#include <stdio.h>
#include "telemetry.h"
#include "hal.h"

static uint32_t frame_counter = 0;

/* Simple CRC-16/CCITT-like checksum for demonstration */
static uint16_t compute_checksum(const telemetry_data_t *data)
{
    uint16_t crc = 0xFFFF;
    const uint8_t *ptr = (const uint8_t *)data;
    /* Exclude the checksum field itself (last 2 bytes) */
    size_t len = sizeof(telemetry_data_t) - sizeof(uint16_t);

    for (size_t i = 0; i < len; i++) {
        crc ^= (uint16_t)ptr[i] << 8;
        for (int j = 0; j < 8; j++) {
            if (crc & 0x8000)
                crc = (crc << 1) ^ 0x1021;
            else
                crc <<= 1;
        }
    }
    return crc;
}

void telemetry_init(void)
{
    frame_counter = 0;
    uart_print("[TELEMETRY] Module initialized\r\n");
}

void telemetry_acquire(telemetry_data_t *data)
{
    if (!data) return;

    memset(data, 0, sizeof(telemetry_data_t));

    data->timestamp   = frame_counter * 1000; /* simulated ms timestamp */
    data->temperature = 215;                   /* 21.5°C */
    data->voltage     = 3300;                  /* 3300 mV = 3.3V */

    /* Fill payload with a recognizable pattern */
    for (int i = 0; i < TELEMETRY_PAYLOAD_SIZE; i++) {
        data->payload[i] = (uint8_t)(frame_counter + i);
    }

    data->checksum = compute_checksum(data);
    frame_counter++;
}

telemetry_status_t telemetry_validate(const telemetry_data_t *data)
{
    if (!data) return TELEMETRY_ERROR;

    /* Voltage sanity check: must be between 2800 mV and 4200 mV */
    if (data->voltage < 2800 || data->voltage > 4200) {
        return TELEMETRY_ERROR;
    }

    /* Temperature sanity check: -400 (-40°C) to +850 (+85°C) */
    if (data->temperature < -400 || data->temperature > 850) {
        return TELEMETRY_ERROR;
    }

    /* Checksum verification */
    if (compute_checksum(data) != data->checksum) {
        return TELEMETRY_ERROR;
    }

    return TELEMETRY_OK;
}

void telemetry_send(const telemetry_data_t *data)
{
    if (!data) return;
    /* In production: serialize + transmit over CAN/UART/SpaceWire */
    printf("[TELEMETRY] Frame #%u | Temp: %d.%d C | Vcc: %u mV | CRC: 0x%04X\n",
           frame_counter - 1,
           data->temperature / 10, data->temperature % 10,
           data->voltage,
           data->checksum);
}
