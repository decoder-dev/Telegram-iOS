#include "ForkVoiceDSP.h"

#include <assert.h>
#include <math.h>
#include <stdint.h>
#include <stdlib.h>

static float correlation(const float *audio, size_t length, size_t stride, size_t lag) {
    float dot = 0.0f;
    float left = 0.0f;
    float right = 0.0f;
    for (size_t i = lag * stride; i < length; i += stride) {
        float a = audio[i];
        float b = audio[i - lag * stride];
        dot += a * b;
        left += a * a;
        right += b * b;
    }
    return dot / sqrtf(left * right);
}

static float measurePitch(const float *audio, uint32_t rate) {
    size_t stride = rate / 4000;
    float measuredRate = (float)rate / (float)stride;
    size_t firstLag = (size_t)(measuredRate / 350.0f);
    size_t lastLag = (size_t)(measuredRate / 60.0f);
    float left = correlation(audio, rate / 2, stride, firstLag - 1);
    float middle = correlation(audio, rate / 2, stride, firstLag);
    for (size_t lag = firstLag; lag < lastLag; lag++) {
        float right = correlation(audio, rate / 2, stride, lag + 1);
        if (middle > 0.69f && middle > left && middle >= right) {
            return measuredRate / (float)lag;
        }
        left = middle;
        middle = right;
    }
    return 0.0f;
}

static float renderTone(uint32_t rate, float frequency) {
    ForkVoiceParams params;
    ForkVoiceParamsSetIdentity(&params);
    assert(ForkVoiceParamsIsIdentity(&params));
    params.referencePitchHz = 190.0f;
    assert(!ForkVoiceParamsIsIdentity(&params));
    ForkVoiceChain *chain = ForkVoiceChainCreate(&params, rate);
    assert(chain != NULL);

    size_t frames = 2 * rate;
    float *audio = malloc((frames + 2) * sizeof(*audio));
    assert(audio != NULL);
    audio[0] = 19.0f;
    audio[frames + 1] = 11.0f;
    for (size_t i = 0; i < frames; i++) {
        float phase = 6.28318530718f * frequency * (float)i / (float)rate;
        audio[i + 1] = 0.17f * sinf(phase) + 0.08f * sinf(2.0f * phase) + 0.045f * sinf(3.0f * phase);
    }
    for (size_t offset = 0; offset < frames; offset += 313) {
        size_t length = frames - offset;
        ForkVoiceChainProcessFloat(chain, audio + 1 + offset, length < 313 ? length : 313, 1, rate);
    }
    assert(audio[0] == 19.0f && audio[frames + 1] == 11.0f);
    float measured = measurePitch(audio + 1 + rate + rate / 2, rate);

    ForkVoiceChainReset(chain);
    float silence[743] = {0};
    ForkVoiceChainProcessFloat(chain, silence, 743, 1, rate);
    for (size_t i = 0; i < 743; i++) {
        assert(silence[i] == 0.0f);
    }
    free(audio);
    ForkVoiceChainDestroy(chain);
    return measured;
}

int main(void) {
    const uint32_t rates[] = {8000, 16000, 44100, 48000, 96000};
    for (size_t i = 0; i < sizeof(rates) / sizeof(rates[0]); i++) {
        float low = renderTone(rates[i], 120.0f);
        float center = renderTone(rates[i], 190.0f);
        float high = renderTone(rates[i], 270.0f);
        // With full correction the measured pitch of a steady tone lands on the 190 Hz
        // reference from any direction (measured 190.5-190.9 through the Python port of the
        // chain at every rate); the ranges keep slack for float32 vs float64 drift.
        assert(low > 178.0f && low < 203.0f);
        assert(center > 178.0f && center < 203.0f);
        assert(high > 178.0f && high < 203.0f);
    }
    return 0;
}
