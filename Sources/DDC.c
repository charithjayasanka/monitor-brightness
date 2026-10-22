#include "DDC.h"
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <CoreGraphics/CoreGraphics.h>
#include <dlfcn.h>
#include <stdlib.h>
#include <stdio.h>
#include <unistd.h>

struct DDCDisplay { CFTypeRef service; uint64_t identifier; uint32_t chipAddress; };
typedef CFTypeRef (*CreateService)(CFAllocatorRef, io_service_t);
typedef IOReturn (*Transfer)(CFTypeRef, uint32_t, uint32_t, void *, uint32_t);
static Transfer readI2C, writeI2C;

int ddc_discover(DDCDisplay **out, int capacity) {
    CreateService create = (CreateService)dlsym(RTLD_DEFAULT, "IOAVServiceCreateWithService");
    readI2C = (Transfer)dlsym(RTLD_DEFAULT, "IOAVServiceReadI2C");
    writeI2C = (Transfer)dlsym(RTLD_DEFAULT, "IOAVServiceWriteI2C");
    if (!create || !readI2C || !writeI2C) return -1;
    io_iterator_t iterator = 0;
    if (IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("DCPAVServiceProxy"), &iterator)) return -1;
    int count = 0;
    io_service_t entry;
    while ((entry = IOIteratorNext(iterator))) {
        CFTypeRef location = IORegistryEntryCreateCFProperty(entry, CFSTR("Location"), NULL, 0);
        if (location && CFEqual(location, CFSTR("External")) && count < capacity) {
            CFTypeRef service = create(kCFAllocatorDefault, entry);
            if (service) {
                DDCDisplay *display = calloc(1, sizeof(*display));
                if (display) {
                    display->service = service;
                    display->chipAddress = 0x37;
                    io_registry_entry_t parent = 0;
                    if (IORegistryEntryGetParentEntry(entry, kIOServicePlane, &parent) == KERN_SUCCESS) {
                        CFTypeRef provider = IORegistryEntryCreateCFProperty(parent, CFSTR("EPICProviderClass"), NULL, 0);
                        if (provider && CFEqual(provider, CFSTR("AppleDCPMCDP29XX"))) display->chipAddress = 0xb7;
                        if (provider) CFRelease(provider);
                        IOObjectRelease(parent);
                    }
                    if (getenv("DDC_DEBUG")) fprintf(stderr, "DDC transport address: 0x%x\n", display->chipAddress);
                    IORegistryEntryGetRegistryEntryID(entry, &display->identifier);
                    out[count++] = display;
                } else CFRelease(service);
            }
        }
        if (location) CFRelease(location);
        IOObjectRelease(entry);
    }
    IOObjectRelease(iterator);
    return count;
}
void ddc_release(DDCDisplay *display) { if (display) { CFRelease(display->service); free(display); } }
uint64_t ddc_id(DDCDisplay *display) { return display->identifier; }

uint32_t ddc_screen_id(DDCDisplay *display) {
    // Match the proxy to its framebuffer, then the framebuffer's exact registry
    // location to a CoreGraphics display. Never guess using discovery order.
    void *framework = dlopen("/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay", RTLD_LAZY);
    if (!framework) return 0;
    typedef CFDictionaryRef (*DisplayInfo)(uint32_t);
    DisplayInfo info = (DisplayInfo)dlsym(framework, "CoreDisplay_DisplayCreateInfoDictionary");
    uint64_t framebuffer = 0;
    io_registry_entry_t root = IORegistryGetRootEntry(kIOMainPortDefault);
    io_iterator_t iterator = 0;
    if (info && root && IORegistryEntryCreateIterator(root, kIOServicePlane, kIORegistryIterateRecursively, &iterator) == KERN_SUCCESS) {
        io_registry_entry_t entry;
        bool found = false;
        while ((entry = IOIteratorNext(iterator))) {
            uint64_t identifier = 0;
            IORegistryEntryGetRegistryEntryID(entry, &identifier);
            if (IOObjectConformsTo(entry, "IOMobileFramebuffer")) framebuffer = identifier;
            found = identifier == display->identifier;
            IOObjectRelease(entry);
            if (found) break;
        }
        if (!found) framebuffer = 0;
        IOObjectRelease(iterator);
    }
    if (root) IOObjectRelease(root);
    uint32_t result = 0, ids[32], count = 0;
    if (info && framebuffer && CGGetOnlineDisplayList(32, ids, &count) == kCGErrorSuccess) {
        for (uint32_t i = 0; i < count; i++) {
            if (CGDisplayIsBuiltin(ids[i])) continue;
            CFDictionaryRef dict = info(ids[i]);
            if (!dict) continue;
            CFTypeRef path = CFDictionaryGetValue(dict, CFSTR("IODisplayLocation"));
            io_registry_entry_t entry = path && CFGetTypeID(path) == CFStringGetTypeID() ? IORegistryEntryCopyFromPath(kIOMainPortDefault, path) : 0;
            uint64_t identifier = 0;
            if (entry) { IORegistryEntryGetRegistryEntryID(entry, &identifier); IOObjectRelease(entry); }
            CFRelease(dict);
            if (identifier == framebuffer) {
                if (result) { result = 0; break; } // Ambiguous: do not target either.
                result = ids[i];
            }
        }
    }
    dlclose(framework);
    return result;
}

bool ddc_decode(const uint8_t *r, size_t length, uint16_t *current, uint16_t *maximum) {
    if (length != 11 || r[0] != 0x6e || r[1] != 0x88 || r[2] != 0x02 || r[3] != 0 || r[4] != 0x10) return false;
    uint8_t checksum = 0x50;
    for (int i = 0; i < 11; i++) checksum ^= r[i];
    if (checksum) return false;
    uint16_t max = (r[6] << 8) | r[7], value = (r[8] << 8) | r[9];
    if (!max || value > max) return false;
    *maximum = max; *current = value;
    return true;
}
bool ddc_read(DDCDisplay *display, uint16_t *current, uint16_t *maximum) {
    // IOAVService supplies the data address; Get VCP uses the 0x6e checksum seed.
    uint8_t request[] = {0x82, 0x01, 0x10, 0xfd};
    for (int attempt = 0; attempt < 3; attempt++) {
        usleep(100000);
        IOReturn sent = writeI2C(display->service, display->chipAddress, 0x51, request, sizeof(request));
        if (sent) continue;
        usleep(200000);
        uint8_t reply[12] = {0};
        IOReturn received = readI2C(display->service, display->chipAddress, 0, reply, sizeof(reply));
        if (getenv("DDC_DEBUG")) {
            fprintf(stderr, "DDC read status: 0x%x; reply:", received);
            for (int i = 0; i < 11; i++) fprintf(stderr, " %02x", reply[i]);
            fprintf(stderr, "\n");
        }
        if (!received && ddc_decode(reply, 11, current, maximum)) return true;
        usleep(40000);
    }
    return false;
}
bool ddc_write(DDCDisplay *display, uint16_t value) {
    uint8_t packet[] = {0x84, 0x03, 0x10, value >> 8, value & 0xff, 0};
    uint8_t checksum = 0x6e ^ 0x51;
    for (int i = 0; i < 5; i++) checksum ^= packet[i];
    packet[5] = checksum;
    for (int attempt = 0; attempt < 3; attempt++) {
        usleep(100000);
        if (!writeI2C(display->service, display->chipAddress, 0x51, packet, sizeof(packet))) return true;
    }
    return false;
}
