#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
typedef struct DDCDisplay DDCDisplay;
int ddc_discover(DDCDisplay **out, int capacity);
void ddc_release(DDCDisplay *display);
uint64_t ddc_id(DDCDisplay *display);
uint32_t ddc_screen_id(DDCDisplay *display);
bool ddc_read(DDCDisplay *display, uint16_t *current, uint16_t *maximum);
bool ddc_write(DDCDisplay *display, uint16_t value);
bool ddc_decode(const uint8_t *reply, size_t length, uint16_t *current, uint16_t *maximum);
