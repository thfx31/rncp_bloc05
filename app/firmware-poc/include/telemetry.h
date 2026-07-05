#ifndef TELEMETRY_H
#define TELEMETRY_H

#include <stdint.h>

#define TELEMETRY_PAYLOAD_SIZE  32

typedef enum {
    TELEMETRY_OK    = 0,
    TELEMETRY_ERROR = 1
} telemetry_status_t;

typedef struct {
    uint32_t timestamp;
    int16_t  temperature;   /* in 0.1°C units */
    uint16_t voltage;       /* in mV */
    uint8_t  payload[TELEMETRY_PAYLOAD_SIZE];
    uint16_t checksum;
} telemetry_data_t;

/* Function prototypes */
void               telemetry_init(void);
void               telemetry_acquire(telemetry_data_t *data);
telemetry_status_t telemetry_validate(const telemetry_data_t *data);
void               telemetry_send(const telemetry_data_t *data);

#endif /* TELEMETRY_H */
