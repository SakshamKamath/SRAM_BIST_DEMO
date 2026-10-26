// SPDX-License-Identifier: Apache-2.0
#ifndef VAD_REFERENCE_H
#define VAD_REFERENCE_H

#include <stddef.h>
#include <stdint.h>

typedef struct {
    uint64_t energy;
    uint16_t zero_crossings;
} vad_features_t;

// Match the baseline's bit-14 sign reconstruction, including ignored bit 15.
static inline vad_features_t vad_reference(const uint16_t *raw, size_t count) {
    vad_features_t result = {0, 0};
    unsigned previous_sign = 0;
    for (size_t i = 0; i < count; ++i) {
        unsigned sign = (raw[i] >> 14) & 1u;
        int32_t sample = (int32_t)(raw[i] & 0x7fffu);
        if (sign) sample -= 0x8000;
        result.energy += (uint64_t)(sample * sample);
        if (i != 0 && sign != previous_sign) ++result.zero_crossings;
        previous_sign = sign;
    }
    return result;
}

static inline int vad_reference_decision(vad_features_t features, int enable,
                                         uint32_t energy_threshold,
                                         uint16_t zcr_threshold) {
    return enable && features.energy > energy_threshold &&
           features.zero_crossings <= zcr_threshold;
}
#endif
