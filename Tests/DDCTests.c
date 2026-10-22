#include "../Sources/DDC.h"
#include <assert.h>
#include <stdio.h>
static void checksum(uint8_t *r) {
    r[10] = 0x50;
    for (int i = 0; i < 10; i++) r[10] ^= r[i];
}
int main(void) {
    uint16_t current = 0, maximum = 0;
    uint8_t reply[] = {0x6e, 0x88, 0x02, 0, 0x10, 0, 0, 100, 0, 40, 0};
    checksum(reply);
    assert(ddc_decode(reply, 11, &current, &maximum) && current == 40 && maximum == 100);
    assert(!ddc_decode(reply, 10, &current, &maximum));
    reply[10] ^= 1;
    assert(!ddc_decode(reply, 11, &current, &maximum));
    reply[3] = 1; checksum(reply);
    assert(!ddc_decode(reply, 11, &current, &maximum));
    reply[3] = 0; reply[4] = 0x12; checksum(reply);
    assert(!ddc_decode(reply, 11, &current, &maximum));
    reply[4] = 0x10; reply[7] = 0; checksum(reply);
    assert(!ddc_decode(reply, 11, &current, &maximum));
    reply[7] = 20; checksum(reply);
    assert(!ddc_decode(reply, 11, &current, &maximum));
    reply[6] = 1; reply[7] = 0; reply[8] = 1; reply[9] = 0; checksum(reply);
    assert(ddc_decode(reply, 11, &current, &maximum) && current == 256 && maximum == 256);
    // Actual CM639-path response: transport success must not become fake brightness.
    const uint8_t adapterReply[] = {0x00, 0xa0, 0x29, 0x50, 0x30, 0x20, 0x35, 0x00, 0x55, 0x50, 0x21};
    assert(!ddc_decode(adapterReply, sizeof(adapterReply), &current, &maximum));
    const uint8_t echoedRequest[] = {0x6e, 0x85, 0xc0, 0x00, 0x00, 0x03, 0x51, 0x82, 0x01, 0x10, 0xfd};
    assert(!ddc_decode(echoedRequest, sizeof(echoedRequest), &current, &maximum));
    puts("DDC response validation passed");
}
