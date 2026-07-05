#ifndef HAL_H
#define HAL_H

#include <stdint.h>

/* LED identifiers */
typedef enum {
    LED_STATUS = 0,
    LED_ERROR  = 1
} led_id_t;

typedef enum {
    LED_OFF = 0,
    LED_ON  = 1
} led_state_t;

/* HAL function prototypes */
void     hal_init(void);
void     hal_delay_ms(uint32_t ms);
void     hal_enter_low_power(void);

void     uart_init(uint32_t baudrate);
void     uart_print(const char *str);
void     uart_print_uint(uint32_t value);

void     led_set(led_id_t led, led_state_t state);

#endif /* HAL_H */
