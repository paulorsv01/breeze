#include "CSMC.h"
#include <IOKit/IOKitLib.h>
#include <stddef.h>
#include <string.h>

typedef struct {
    uint32_t key;
    struct { uint8_t major, minor, build, reserved; uint16_t release; } version;
    struct { uint16_t version, length; uint32_t cpu, gpu, memory; } limits;
    struct { uint32_t size, type; uint8_t attributes; } info;
    uint8_t result, status, command;
    uint32_t index;
    uint8_t bytes[32];
} SMCRequest;

_Static_assert(sizeof(SMCRequest) == 80, "AppleSMC ABI requires 80 bytes");
_Static_assert(offsetof(SMCRequest, bytes) == 48, "AppleSMC payload offset");

static int32_t call(uint32_t connection, SMCRequest *input, SMCRequest *output) {
    size_t size = sizeof(*output);
    kern_return_t status = IOConnectCallStructMethod(connection, 2, input, sizeof(*input), output, &size);
    if (status != KERN_SUCCESS) return status;
    if (size != sizeof(*output)) return kIOReturnBadArgument;
    return output->result ? 0x10000 + output->result : 0;
}

int32_t breeze_smc_open(uint32_t *connection) {
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    if (!service) return kIOReturnNotFound;
    kern_return_t status = IOServiceOpen(service, mach_task_self(), 0, connection);
    IOObjectRelease(service);
    return status;
}

void breeze_smc_close(uint32_t connection) { IOServiceClose(connection); }

int32_t breeze_smc_read(uint32_t connection, uint32_t key, BreezeSMCValue *value) {
    SMCRequest input = {0}, output = {0};
    input.key = key;
    input.command = 9;
    int32_t status = call(connection, &input, &output);
    if (status) return status;
    if (output.info.size == 0 || output.info.size > 32) return kIOReturnBadArgument;
    value->size = output.info.size;
    value->type = output.info.type;
    input.info.size = value->size;
    input.command = 5;
    memset(&output, 0, sizeof(output));
    status = call(connection, &input, &output);
    if (!status) memcpy(value->bytes, output.bytes, value->size);
    return status;
}

int32_t breeze_smc_key_at(uint32_t connection, uint32_t index, uint32_t *key) {
    SMCRequest input = {0}, output = {0};
    input.index = index;
    input.command = 8;
    int32_t status = call(connection, &input, &output);
    if (!status) *key = output.key;
    return status;
}

int32_t breeze_smc_write(uint32_t connection, uint32_t key, const BreezeSMCValue *value) {
    if (value->size == 0 || value->size > 32) return kIOReturnBadArgument;
    SMCRequest input = {0}, output = {0};
    input.key = key;
    input.info.size = value->size;
    input.command = 6;
    memcpy(input.bytes, value->bytes, value->size);
    return call(connection, &input, &output);
}
