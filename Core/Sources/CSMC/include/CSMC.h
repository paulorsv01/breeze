#pragma once
#include <stdint.h>

typedef struct {
    uint32_t type;
    uint32_t size;
    uint8_t bytes[32];
} BreezeSMCValue;

int32_t breeze_smc_open(uint32_t *connection);
void breeze_smc_close(uint32_t connection);
int32_t breeze_smc_read(uint32_t connection, uint32_t key, BreezeSMCValue *value);
int32_t breeze_smc_key_at(uint32_t connection, uint32_t index, uint32_t *key);
int32_t breeze_smc_write(uint32_t connection, uint32_t key, const BreezeSMCValue *value);
