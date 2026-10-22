// Read-only brightness queries. Does not issue Set VCP commands.
#include "../Sources/DDC.c"
int main(void) {
    DDCDisplay *displays[16];
    int count = ddc_discover(displays, 16), valid = 0, tested = 0;
    puts("service,address,delay_ms,repeats,read_offset,read_length,write_status,read_status,valid,reply");
    for (int d = 0; d < count; d++) {
        unsigned delays[] = {50, 200, 500};
        for (int a = 0; a < 2; a++)
        for (int t = 0; t < 3; t++)
        for (int repeats = 1; repeats <= 2; repeats++)
        for (int offset = 0; offset < 2; offset++)
        for (int len = 11; len <= 12; len++) {
            // The alternate route only needs the conservative 500 ms test.
            if (a && t != 2) continue;
            uint32_t address = a ? 0xb7 : 0x37;
            uint8_t request[] = {0x82, 0x01, 0x10, 0xfd};
            IOReturn sent = 0;
            for (int cycle = 0; cycle < repeats; cycle++) {
                usleep(50000);
                sent = writeI2C(displays[d]->service, address, 0x51, request, 4);
                if (sent) break;
            }
            usleep(delays[t] * 1000);
            uint8_t reply[12] = {0};
            IOReturn received = readI2C(displays[d]->service, address, offset ? 0x51 : 0, reply, len);
            uint16_t current = 0, maximum = 0;
            bool ok = !sent && !received && ddc_decode(reply, 11, &current, &maximum);
            tested++; valid += ok;
            printf("%llu,%02x,%u,%d,%02x,%d,%08x,%08x,%d,", (unsigned long long)ddc_id(displays[d]), address, delays[t], repeats, offset ? 0x51 : 0, len, sent, received, ok);
            for (int i = 0; i < len; i++) printf("%02x", reply[i]);
            puts(""); fflush(stdout);
        }
        ddc_release(displays[d]);
    }
    fprintf(stderr, "Validated replies: %d/%d; external services: %d\n", valid, tested, count);
    return valid ? 0 : 1;
}
