// SPDX-License-Identifier: Apache-2.0
#include <assert.h>
#include <stdio.h>
#include "vad_reference.h"

int main(void) {
    const uint16_t samples[] = {0x4000, 0x3fff, 0xffff, 0x8000, 0x8002};
    vad_features_t features = vad_reference(samples, 5);
    assert(features.energy == UINT64_C(536838150));
    assert(features.zero_crossings == 3);
    assert(!vad_reference_decision(features, 1, 536838150, 3));
    assert(vad_reference_decision(features, 1, 536838149, 3));
    assert(!vad_reference_decision(features, 1, 536838149, 2));
    assert(!vad_reference_decision(features, 0, 0, 3));
    uint16_t maximum_energy[512];
    for (size_t i = 0; i < 512; ++i) maximum_energy[i] = 0xc000;
    features = vad_reference(maximum_energy, 512);
    assert(features.energy == UINT64_C(137438953472));
    assert(features.zero_crossings == 0);
    features = vad_reference(0, 0);
    assert(features.energy == 0 && features.zero_crossings == 0);
    puts("PASS test_vad_reference");
    return 0;
}
