#include "ForkVoiceDSP.h"

#include <math.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>

// MARK: - Common pieces

#define FV_PI 3.14159265358979f
#define FV_SINE_TABLE_SIZE 2048
#define FV_BLOCK_FRAMES 1024
#define FV_CONTROL_INTERVAL 32
#define FV_MAX_CHANNELS 8
#define FV_PITCH_ANALYSIS_RATE 4000
#define FV_PITCH_ANALYSIS_HISTORY 256
#define FV_PITCH_ANALYSIS_WINDOW 128
#define FV_PITCH_ANALYSIS_MAX_LAG 72

typedef struct FVBiquad {
    float b0;
    float b1;
    float b2;
    float a1;
    float a2;
    float z1;
    float z2;
} FVBiquad;

static inline float fv_biquad_run(FVBiquad *f, float x) {
    float y = f->b0 * x + f->z1;
    f->z1 = f->b1 * x - f->a1 * y + f->z2;
    f->z2 = f->b2 * x - f->a2 * y;
    return y;
}

static float fv_clamp_frequency(float frequency, float sampleRate) {
    float limit = sampleRate * 0.45f;
    if (frequency > limit) {
        return limit;
    }
    if (frequency < 10.0f) {
        return 10.0f;
    }
    return frequency;
}

static void fv_biquad_set(FVBiquad *f, float b0, float b1, float b2, float a0, float a1, float a2) {
    float inv = 1.0f / a0;
    f->b0 = b0 * inv;
    f->b1 = b1 * inv;
    f->b2 = b2 * inv;
    f->a1 = a1 * inv;
    f->a2 = a2 * inv;
}

static void fv_biquad_identity(FVBiquad *f) {
    f->b0 = 1.0f;
    f->b1 = 0.0f;
    f->b2 = 0.0f;
    f->a1 = 0.0f;
    f->a2 = 0.0f;
}

// Coefficient setters keep the state (z1, z2): a change of gain does not click.
static void fv_biquad_peak(FVBiquad *f, float sampleRate, float frequency, float q, float gainDb) {
    float A = powf(10.0f, gainDb / 40.0f);
    float w0 = 2.0f * FV_PI * fv_clamp_frequency(frequency, sampleRate) / sampleRate;
    float cosw = cosf(w0);
    float alpha = sinf(w0) / (2.0f * q);
    fv_biquad_set(f, 1.0f + alpha * A, -2.0f * cosw, 1.0f - alpha * A, 1.0f + alpha / A, -2.0f * cosw, 1.0f - alpha / A);
}

static void fv_biquad_low_shelf(FVBiquad *f, float sampleRate, float frequency, float gainDb) {
    float A = powf(10.0f, gainDb / 40.0f);
    float w0 = 2.0f * FV_PI * fv_clamp_frequency(frequency, sampleRate) / sampleRate;
    float cosw = cosf(w0);
    float alpha = sinf(w0) * 0.5f * 1.41421356f;
    float sqrtA2alpha = 2.0f * sqrtf(A) * alpha;
    fv_biquad_set(f,
        A * ((A + 1.0f) - (A - 1.0f) * cosw + sqrtA2alpha),
        2.0f * A * ((A - 1.0f) - (A + 1.0f) * cosw),
        A * ((A + 1.0f) - (A - 1.0f) * cosw - sqrtA2alpha),
        (A + 1.0f) + (A - 1.0f) * cosw + sqrtA2alpha,
        -2.0f * ((A - 1.0f) + (A + 1.0f) * cosw),
        (A + 1.0f) + (A - 1.0f) * cosw - sqrtA2alpha);
}

static void fv_biquad_high_shelf(FVBiquad *f, float sampleRate, float frequency, float gainDb) {
    float A = powf(10.0f, gainDb / 40.0f);
    float w0 = 2.0f * FV_PI * fv_clamp_frequency(frequency, sampleRate) / sampleRate;
    float cosw = cosf(w0);
    float alpha = sinf(w0) * 0.5f * 1.41421356f;
    float sqrtA2alpha = 2.0f * sqrtf(A) * alpha;
    fv_biquad_set(f,
        A * ((A + 1.0f) + (A - 1.0f) * cosw + sqrtA2alpha),
        -2.0f * A * ((A - 1.0f) + (A + 1.0f) * cosw),
        A * ((A + 1.0f) + (A - 1.0f) * cosw - sqrtA2alpha),
        (A + 1.0f) - (A - 1.0f) * cosw + sqrtA2alpha,
        2.0f * ((A - 1.0f) - (A + 1.0f) * cosw),
        (A + 1.0f) - (A - 1.0f) * cosw - sqrtA2alpha);
}

static void fv_biquad_high_pass(FVBiquad *f, float sampleRate, float frequency) {
    float w0 = 2.0f * FV_PI * fv_clamp_frequency(frequency, sampleRate) / sampleRate;
    float cosw = cosf(w0);
    float alpha = sinf(w0) / (2.0f * 0.7071f);
    fv_biquad_set(f, (1.0f + cosw) * 0.5f, -(1.0f + cosw), (1.0f + cosw) * 0.5f, 1.0f + alpha, -2.0f * cosw, 1.0f - alpha);
}

static void fv_biquad_low_pass(FVBiquad *f, float sampleRate, float frequency) {
    float w0 = 2.0f * FV_PI * fv_clamp_frequency(frequency, sampleRate) / sampleRate;
    float cosw = cosf(w0);
    float alpha = sinf(w0) / (2.0f * 0.7071f);
    fv_biquad_set(f, (1.0f - cosw) * 0.5f, 1.0f - cosw, (1.0f - cosw) * 0.5f, 1.0f + alpha, -2.0f * cosw, 1.0f - alpha);
}

static inline float fv_fast_tanh(float x) {
    if (x > 3.0f) {
        return 1.0f;
    }
    if (x < -3.0f) {
        return -1.0f;
    }
    float x2 = x * x;
    return x * (27.0f + x2) / (27.0f + 9.0f * x2);
}

static inline float fv_soft_limit(float x) {
    float a = fabsf(x);
    if (a <= 0.8f) {
        return x;
    }
    float limited = 0.8f + 0.2f * fv_fast_tanh((a - 0.8f) / 0.2f);
    return x < 0.0f ? -limited : limited;
}

static inline int16_t fv_float_to_int16(float x) {
    float scaled = x * 32767.0f;
    if (scaled > 32767.0f) {
        return 32767;
    }
    if (scaled < -32768.0f) {
        return -32768;
    }
    return (int16_t)lrintf(scaled);
}

static uint32_t fv_next_power_of_two(uint32_t value) {
    uint32_t result = 1;
    while (result < value && result < (1u << 30)) {
        result <<= 1;
    }
    return result;
}

static float fv_clampf(float value, float minValue, float maxValue) {
    if (!(value == value)) {
        return minValue;
    }
    if (value < minValue) {
        return minValue;
    }
    if (value > maxValue) {
        return maxValue;
    }
    return value;
}

// MARK: - Voice parameters

void ForkVoiceParamsSetIdentity(ForkVoiceParams *params) {
    memset(params, 0, sizeof(ForkVoiceParams));
    params->bitcrushBits = 16.0f;
    params->echoDelayMs = 250.0f;
    params->reverbSize = 0.5f;
    params->wet = 1.0f;
}

static ForkVoiceParams fv_sanitized_params(const ForkVoiceParams *source) {
    ForkVoiceParams p = *source;
    p.pitchSemitones = fv_clampf(p.pitchSemitones, -12.0f, 12.0f);
    p.timbre = fv_clampf(p.timbre, -1.0f, 1.0f);
    p.bassDb = fv_clampf(p.bassDb, -12.0f, 12.0f);
    p.midDb = fv_clampf(p.midDb, -12.0f, 12.0f);
    p.trebleDb = fv_clampf(p.trebleDb, -12.0f, 12.0f);
    p.telephone = fv_clampf(p.telephone, 0.0f, 1.0f);
    p.distortion = fv_clampf(p.distortion, 0.0f, 1.0f);
    p.bitcrushBits = fv_clampf(p.bitcrushBits, 2.0f, 16.0f);
    p.ringModHz = fv_clampf(p.ringModHz, 0.0f, 1000.0f);
    p.ringModMix = fv_clampf(p.ringModMix, 0.0f, 1.0f);
    p.chorus = fv_clampf(p.chorus, 0.0f, 1.0f);
    p.flanger = fv_clampf(p.flanger, 0.0f, 1.0f);
    p.echoMix = fv_clampf(p.echoMix, 0.0f, 1.0f);
    p.echoDelayMs = fv_clampf(p.echoDelayMs, 40.0f, 800.0f);
    p.echoFeedback = fv_clampf(p.echoFeedback, 0.0f, 0.8f);
    p.reverbMix = fv_clampf(p.reverbMix, 0.0f, 1.0f);
    p.reverbSize = fv_clampf(p.reverbSize, 0.0f, 1.0f);
    p.breathiness = fv_clampf(p.breathiness, 0.0f, 1.0f);
    p.compression = fv_clampf(p.compression, 0.0f, 1.0f);
    p.gainDb = fv_clampf(p.gainDb, -12.0f, 12.0f);
    p.vibratoRateHz = fv_clampf(p.vibratoRateHz, 0.0f, 12.0f);
    p.vibratoDepth = fv_clampf(p.vibratoDepth, 0.0f, 1.0f);
    p.jitter = fv_clampf(p.jitter, 0.0f, 1.0f);
    p.wet = fv_clampf(p.wet, 0.0f, 1.0f);
    p.referencePitchHz = p.referencePitchHz >= 65.0f ? fv_clampf(p.referencePitchHz, 65.0f, 350.0f) : 0.0f;
    return p;
}

static bool fv_pitch_active(const ForkVoiceParams *p) {
    if (fabsf(p->pitchSemitones) > 0.01f || p->referencePitchHz > 0.0f) {
        return true;
    }
    if (p->vibratoDepth > 0.001f && p->vibratoRateHz > 0.01f) {
        return true;
    }
    return p->jitter > 0.001f;
}

bool ForkVoiceParamsIsIdentity(const ForkVoiceParams *source) {
    ForkVoiceParams p = fv_sanitized_params(source);
    if (p.wet < 0.001f) {
        return fabsf(p.gainDb) < 0.01f;
    }
    if (fv_pitch_active(&p)) {
        return false;
    }
    if (fabsf(p.timbre) > 0.01f || fabsf(p.bassDb) > 0.01f || fabsf(p.midDb) > 0.01f || fabsf(p.trebleDb) > 0.01f) {
        return false;
    }
    if (p.telephone > 0.001f || p.distortion > 0.001f || p.bitcrushBits < 15.99f) {
        return false;
    }
    if (p.ringModHz > 0.01f && p.ringModMix > 0.001f) {
        return false;
    }
    if (p.chorus > 0.001f || p.flanger > 0.001f || p.echoMix > 0.001f || p.reverbMix > 0.001f) {
        return false;
    }
    if (p.breathiness > 0.001f || p.compression > 0.001f || fabsf(p.gainDb) > 0.01f) {
        return false;
    }
    return true;
}

// Only queried at capture setup. Audio processing uses the capture's private copy.
typedef struct {
    bool enabled;
    ForkVoiceParams params;
} FVCaptureSettings;

static pthread_mutex_t fv_capture_settings_mutex = PTHREAD_MUTEX_INITIALIZER;
static FVCaptureSettings fv_call_settings;
static FVCaptureSettings fv_round_video_settings;

static void fv_capture_set_params(FVCaptureSettings *settings, const ForkVoiceParams *params) {
    pthread_mutex_lock(&fv_capture_settings_mutex);
    settings->enabled = params != NULL;
    if (params != NULL) {
        settings->params = *params;
    }
    pthread_mutex_unlock(&fv_capture_settings_mutex);
}

static bool fv_capture_get_params(const FVCaptureSettings *settings, ForkVoiceParams *params) {
    pthread_mutex_lock(&fv_capture_settings_mutex);
    bool enabled = settings->enabled;
    if (enabled) {
        *params = settings->params;
    }
    pthread_mutex_unlock(&fv_capture_settings_mutex);
    return enabled;
}

void ForkVoiceCaptureSetCallParams(const ForkVoiceParams *params) {
    fv_capture_set_params(&fv_call_settings, params);
}

bool ForkVoiceCaptureGetCallParams(ForkVoiceParams *params) {
    return fv_capture_get_params(&fv_call_settings, params);
}

void ForkVoiceCaptureSetRoundVideoParams(const ForkVoiceParams *params) {
    fv_capture_set_params(&fv_round_video_settings, params);
}

bool ForkVoiceCaptureGetRoundVideoParams(ForkVoiceParams *params) {
    return fv_capture_get_params(&fv_round_video_settings, params);
}

// MARK: - Voice chain

typedef struct {
    float history[FV_PITCH_ANALYSIS_HISTORY];
    uint32_t writeIndex;
    uint32_t samplesUntilEstimate;
    uint32_t decimationCount;
    float decimationSum;
    float goalSemitones;
    float shiftSemitones;
    bool hasEstimate;
} FVPitchAnalysis;

struct ForkVoiceChain {
    ForkVoiceParams params;
    uint32_t maxSampleRate;
    uint32_t sampleRate;
    float sineTable[FV_SINE_TABLE_SIZE + 1];
    float scratch[FV_BLOCK_FRAMES];
    uint32_t rng;

    // Pitch: two crossfaded taps on one delay line.
    bool pitchActive;
    float *pitchBuffer;
    uint32_t pitchMask;
    uint32_t pitchWrite;
    float pitchWindow;
    float pitchPhase;
    float pitchRatio;
    uint32_t controlCounter;
    float vibratoPhase;
    float vibratoIncrement;
    float jitterValue;
    float jitterTarget;
    uint32_t jitterCounter;
    uint32_t jitterPeriod;
    FVPitchAnalysis pitchAnalysis;
    uint32_t pitchAnalysisDecimation;
    float pitchAnalysisRate;
    float pitchAnalysisSmoothing;

    // Filters.
    bool timbreActive;
    FVBiquad timbreLow;
    FVBiquad timbreHigh;
    bool eqActive;
    FVBiquad eqLow;
    FVBiquad eqMid;
    FVBiquad eqHigh;
    bool phoneActive;
    FVBiquad phoneHigh;
    FVBiquad phoneLow;

    // Distortion and bitcrusher.
    float distortionDrive;
    float distortionNorm;
    float bitcrushLevels;

    // Ring modulator.
    bool ringActive;
    float ringPhase;
    float ringIncrement;

    // Chorus.
    float *chorusBuffer;
    uint32_t chorusMask;
    uint32_t chorusWrite;
    float chorusPhase;
    float chorusIncrement;
    float chorusBase;
    float chorusDepth;

    // Flanger.
    float *flangerBuffer;
    uint32_t flangerMask;
    uint32_t flangerWrite;
    float flangerPhase;
    float flangerIncrement;
    float flangerBase;
    float flangerDepth;

    // Echo.
    float *echoBuffer;
    uint32_t echoMask;
    uint32_t echoWrite;
    uint32_t echoDelay;

    // Reverb (4 damped combs + 2 allpasses).
    float *combBuffers[4];
    uint32_t combCapacity[4];
    uint32_t combLength[4];
    uint32_t combIndex[4];
    float combStore[4];
    float combFeedback;
    float combDamp;
    float *allpassBuffers[2];
    uint32_t allpassCapacity[2];
    uint32_t allpassLength[2];
    uint32_t allpassIndex[2];

    // Breath.
    float breathEnvelope;
    float breathRelease;
    float breathHighPass;
    float breathPreviousNoise;
    float breathCoefficient;

    // Compressor.
    bool compressorActive;
    float compressorEnvelope;
    float compressorGain;
    float compressorTargetGain;
    float compressorThresholdDb;
    float compressorRatio;
    float compressorAttack;
    float compressorRelease;
    float compressorMakeupDb;
    uint32_t compressorCounter;

    float gainLinear;
};

static const float fv_comb_tuning[4] = { 1116.0f, 1188.0f, 1277.0f, 1356.0f };
static const float fv_allpass_tuning[2] = { 556.0f, 441.0f };

static inline float fv_chain_sine(const ForkVoiceChain *chain, float phase) {
    float position = phase * (float)FV_SINE_TABLE_SIZE;
    int index = (int)position;
    if (index < 0) {
        index = 0;
    }
    if (index >= FV_SINE_TABLE_SIZE) {
        index = FV_SINE_TABLE_SIZE - 1;
    }
    float frac = position - (float)index;
    return chain->sineTable[index] + frac * (chain->sineTable[index + 1] - chain->sineTable[index]);
}

static inline float fv_wrap_phase(float phase) {
    if (phase >= 1.0f) {
        phase -= floorf(phase);
    } else if (phase < 0.0f) {
        phase -= floorf(phase);
    }
    return phase;
}

static inline uint32_t fv_next_random(uint32_t *state) {
    uint32_t x = *state;
    x ^= x << 13;
    x ^= x >> 17;
    x ^= x << 5;
    *state = x;
    return x;
}

static inline float fv_random_bipolar(uint32_t *state) {
    return (float)(fv_next_random(state) >> 8) * (1.0f / 8388608.0f) - 1.0f;
}

static inline float fv_delay_read(const float *buffer, uint32_t mask, uint32_t writeIndex, float delay) {
    float position = (float)writeIndex - 1.0f - delay;
    float size = (float)(mask + 1);
    while (position < 0.0f) {
        position += size;
    }
    uint32_t i0 = ((uint32_t)position) & mask;
    float frac = position - floorf(position);
    uint32_t i1 = (i0 + 1) & mask;
    return buffer[i0] + frac * (buffer[i1] - buffer[i0]);
}

static float *fv_alloc_buffer(uint32_t count) {
    return (float *)calloc(count, sizeof(float));
}

ForkVoiceChain *ForkVoiceChainCreate(const ForkVoiceParams *params, uint32_t maxSampleRate) {
    ForkVoiceChain *chain = (ForkVoiceChain *)calloc(1, sizeof(ForkVoiceChain));
    if (chain == NULL) {
        return NULL;
    }
    chain->params = fv_sanitized_params(params);
    if (maxSampleRate < 8000) {
        maxSampleRate = 8000;
    }
    if (maxSampleRate > 96000) {
        maxSampleRate = 96000;
    }
    chain->maxSampleRate = maxSampleRate;
    chain->rng = 0x9E3779B9u ^ (uint32_t)(uintptr_t)chain;
    if (chain->rng == 0) {
        chain->rng = 1;
    }
    for (int i = 0; i <= FV_SINE_TABLE_SIZE; i++) {
        chain->sineTable[i] = sinf(2.0f * FV_PI * (float)i / (float)FV_SINE_TABLE_SIZE);
    }

    const ForkVoiceParams *p = &chain->params;
    float maxRate = (float)maxSampleRate;
    bool failed = false;

    chain->pitchActive = fv_pitch_active(p);
    if (chain->pitchActive) {
        uint32_t size = fv_next_power_of_two((uint32_t)(maxRate * 0.1f));
        chain->pitchBuffer = fv_alloc_buffer(size);
        chain->pitchMask = size - 1;
        failed = failed || chain->pitchBuffer == NULL;
    }
    if (p->chorus > 0.001f) {
        uint32_t size = fv_next_power_of_two((uint32_t)(maxRate * 0.04f));
        chain->chorusBuffer = fv_alloc_buffer(size);
        chain->chorusMask = size - 1;
        failed = failed || chain->chorusBuffer == NULL;
    }
    if (p->flanger > 0.001f) {
        uint32_t size = fv_next_power_of_two((uint32_t)(maxRate * 0.012f));
        chain->flangerBuffer = fv_alloc_buffer(size);
        chain->flangerMask = size - 1;
        failed = failed || chain->flangerBuffer == NULL;
    }
    if (p->echoMix > 0.001f) {
        uint32_t size = fv_next_power_of_two((uint32_t)(maxRate * 0.82f));
        chain->echoBuffer = fv_alloc_buffer(size);
        chain->echoMask = size - 1;
        failed = failed || chain->echoBuffer == NULL;
    }
    if (p->reverbMix > 0.001f) {
        for (int i = 0; i < 4; i++) {
            uint32_t capacity = (uint32_t)(fv_comb_tuning[i] * maxRate / 44100.0f * 1.35f) + 2;
            chain->combBuffers[i] = fv_alloc_buffer(capacity);
            chain->combCapacity[i] = capacity;
            failed = failed || chain->combBuffers[i] == NULL;
        }
        for (int i = 0; i < 2; i++) {
            uint32_t capacity = (uint32_t)(fv_allpass_tuning[i] * maxRate / 44100.0f) + 2;
            chain->allpassBuffers[i] = fv_alloc_buffer(capacity);
            chain->allpassCapacity[i] = capacity;
            failed = failed || chain->allpassBuffers[i] == NULL;
        }
    }
    if (failed) {
        ForkVoiceChainDestroy(chain);
        return NULL;
    }
    return chain;
}

void ForkVoiceChainDestroy(ForkVoiceChain *chain) {
    if (chain == NULL) {
        return;
    }
    free(chain->pitchBuffer);
    free(chain->chorusBuffer);
    free(chain->flangerBuffer);
    free(chain->echoBuffer);
    for (int i = 0; i < 4; i++) {
        free(chain->combBuffers[i]);
    }
    for (int i = 0; i < 2; i++) {
        free(chain->allpassBuffers[i]);
    }
    free(chain);
}

static void fv_clear_biquad(FVBiquad *f) {
    f->z1 = 0.0f;
    f->z2 = 0.0f;
}

void ForkVoiceChainReset(ForkVoiceChain *chain) {
    if (chain->pitchBuffer != NULL) {
        memset(chain->pitchBuffer, 0, sizeof(float) * (chain->pitchMask + 1));
    }
    if (chain->chorusBuffer != NULL) {
        memset(chain->chorusBuffer, 0, sizeof(float) * (chain->chorusMask + 1));
    }
    if (chain->flangerBuffer != NULL) {
        memset(chain->flangerBuffer, 0, sizeof(float) * (chain->flangerMask + 1));
    }
    if (chain->echoBuffer != NULL) {
        memset(chain->echoBuffer, 0, sizeof(float) * (chain->echoMask + 1));
    }
    for (int i = 0; i < 4; i++) {
        if (chain->combBuffers[i] != NULL) {
            memset(chain->combBuffers[i], 0, sizeof(float) * chain->combCapacity[i]);
        }
        chain->combIndex[i] = 0;
        chain->combStore[i] = 0.0f;
    }
    for (int i = 0; i < 2; i++) {
        if (chain->allpassBuffers[i] != NULL) {
            memset(chain->allpassBuffers[i], 0, sizeof(float) * chain->allpassCapacity[i]);
        }
        chain->allpassIndex[i] = 0;
    }
    fv_clear_biquad(&chain->timbreLow);
    fv_clear_biquad(&chain->timbreHigh);
    fv_clear_biquad(&chain->eqLow);
    fv_clear_biquad(&chain->eqMid);
    fv_clear_biquad(&chain->eqHigh);
    fv_clear_biquad(&chain->phoneHigh);
    fv_clear_biquad(&chain->phoneLow);
    chain->pitchWrite = 0;
    chain->pitchPhase = 0.0f;
    chain->controlCounter = 0;
    chain->vibratoPhase = 0.0f;
    chain->jitterValue = 0.0f;
    chain->jitterTarget = 0.0f;
    chain->jitterCounter = 0;
    if (chain->params.referencePitchHz > 0.0f) {
        memset(&chain->pitchAnalysis, 0, sizeof(chain->pitchAnalysis));
        chain->pitchAnalysis.samplesUntilEstimate = FV_PITCH_ANALYSIS_HISTORY;
    }
    chain->ringPhase = 0.0f;
    chain->chorusWrite = 0;
    chain->chorusPhase = 0.0f;
    chain->flangerWrite = 0;
    chain->flangerPhase = 0.0f;
    chain->echoWrite = 0;
    chain->breathEnvelope = 0.0f;
    chain->breathHighPass = 0.0f;
    chain->breathPreviousNoise = 0.0f;
    chain->compressorEnvelope = 0.0f;
    chain->compressorGain = 1.0f;
    chain->compressorTargetGain = 1.0f;
    chain->compressorCounter = 0;
}

/// Everything that depends on the sample rate. Math only, no allocation: callable on the realtime thread.
static void fv_chain_configure(ForkVoiceChain *chain, uint32_t sampleRate) {
    const ForkVoiceParams *p = &chain->params;
    float rate = (float)sampleRate;
    chain->sampleRate = sampleRate;

    if (chain->pitchActive) {
        float window = rate * 0.045f;
        float limit = (float)chain->pitchMask - 4.0f;
        if (window > limit) {
            window = limit;
        }
        if (window < 64.0f) {
            window = 64.0f;
        }
        chain->pitchWindow = window;
        chain->pitchRatio = powf(2.0f, p->pitchSemitones / 12.0f);
        chain->vibratoIncrement = p->vibratoRateHz * (float)FV_CONTROL_INTERVAL / rate;
        chain->jitterPeriod = (uint32_t)(rate * 0.15f / (float)FV_CONTROL_INTERVAL) + 1;
        if (p->referencePitchHz > 0.0f) {
            chain->pitchAnalysisDecimation = (uint32_t)fmaxf(1.0f, roundf(rate / FV_PITCH_ANALYSIS_RATE));
            chain->pitchAnalysisRate = rate / (float)chain->pitchAnalysisDecimation;
            chain->pitchAnalysisSmoothing = 1.0f - expf(-(float)FV_CONTROL_INTERVAL / (0.18f * rate));
        }
    }

    chain->timbreActive = fabsf(p->timbre) > 0.01f;
    if (chain->timbreActive) {
        fv_biquad_low_shelf(&chain->timbreLow, rate, 300.0f, -6.0f * p->timbre);
        fv_biquad_high_shelf(&chain->timbreHigh, rate, 2500.0f, 9.0f * p->timbre);
    }
    chain->eqActive = fabsf(p->bassDb) > 0.01f || fabsf(p->midDb) > 0.01f || fabsf(p->trebleDb) > 0.01f;
    if (chain->eqActive) {
        fv_biquad_low_shelf(&chain->eqLow, rate, 200.0f, p->bassDb);
        fv_biquad_peak(&chain->eqMid, rate, 1000.0f, 0.8f, p->midDb);
        fv_biquad_high_shelf(&chain->eqHigh, rate, 4000.0f, p->trebleDb);
    }
    chain->phoneActive = p->telephone > 0.001f;
    if (chain->phoneActive) {
        fv_biquad_high_pass(&chain->phoneHigh, rate, 300.0f);
        fv_biquad_low_pass(&chain->phoneLow, rate, 3400.0f);
    }

    chain->distortionDrive = 1.0f + 14.0f * p->distortion;
    chain->distortionNorm = 1.0f / fv_fast_tanh(chain->distortionDrive);
    chain->bitcrushLevels = powf(2.0f, p->bitcrushBits - 1.0f);

    chain->ringActive = p->ringModHz > 0.01f && p->ringModMix > 0.001f;
    chain->ringIncrement = p->ringModHz / rate;

    if (chain->chorusBuffer != NULL) {
        chain->chorusIncrement = 0.8f / rate;
        chain->chorusBase = rate * 0.02f;
        chain->chorusDepth = rate * 0.005f;
        float limit = (float)chain->chorusMask - 2.0f;
        if (chain->chorusBase + chain->chorusDepth > limit) {
            chain->chorusBase = limit * 0.7f;
            chain->chorusDepth = limit * 0.25f;
        }
    }
    if (chain->flangerBuffer != NULL) {
        chain->flangerIncrement = 0.25f / rate;
        chain->flangerBase = rate * 0.0035f;
        chain->flangerDepth = rate * 0.0025f;
        float limit = (float)chain->flangerMask - 2.0f;
        if (chain->flangerBase + chain->flangerDepth > limit) {
            chain->flangerBase = limit * 0.55f;
            chain->flangerDepth = limit * 0.4f;
        }
    }
    if (chain->echoBuffer != NULL) {
        uint32_t delay = (uint32_t)(p->echoDelayMs * 0.001f * rate);
        if (delay > chain->echoMask) {
            delay = chain->echoMask;
        }
        if (delay < 1) {
            delay = 1;
        }
        chain->echoDelay = delay;
    }
    if (chain->combBuffers[0] != NULL) {
        float sizeScale = 0.75f + 0.5f * p->reverbSize;
        for (int i = 0; i < 4; i++) {
            uint32_t length = (uint32_t)(fv_comb_tuning[i] * rate / 44100.0f * sizeScale);
            if (length >= chain->combCapacity[i]) {
                length = chain->combCapacity[i] - 1;
            }
            if (length < 1) {
                length = 1;
            }
            chain->combLength[i] = length;
            chain->combIndex[i] = 0;
        }
        for (int i = 0; i < 2; i++) {
            uint32_t length = (uint32_t)(fv_allpass_tuning[i] * rate / 44100.0f);
            if (length >= chain->allpassCapacity[i]) {
                length = chain->allpassCapacity[i] - 1;
            }
            if (length < 1) {
                length = 1;
            }
            chain->allpassLength[i] = length;
            chain->allpassIndex[i] = 0;
        }
        chain->combFeedback = 0.70f + 0.25f * p->reverbSize;
        chain->combDamp = 0.3f;
    }

    chain->breathRelease = expf(-1.0f / (0.03f * rate));
    chain->breathCoefficient = expf(-2.0f * FV_PI * 2000.0f / rate);

    chain->compressorActive = p->compression > 0.001f;
    if (chain->compressorActive) {
        chain->compressorThresholdDb = -8.0f - 22.0f * p->compression;
        chain->compressorRatio = 1.0f + 5.0f * p->compression;
        chain->compressorAttack = 1.0f - expf(-1.0f / (0.005f * rate));
        chain->compressorRelease = 1.0f - expf(-1.0f / (0.08f * rate));
        chain->compressorMakeupDb = -chain->compressorThresholdDb * (1.0f - 1.0f / chain->compressorRatio) * 0.5f;
    }
    chain->gainLinear = powf(10.0f, p->gainDb / 20.0f);

    ForkVoiceChainReset(chain);
}

static void fv_pitch_analysis_estimate(ForkVoiceChain *chain) {
    FVPitchAnalysis *analysis = &chain->pitchAnalysis;
    const uint32_t mask = FV_PITCH_ANALYSIS_HISTORY - 1;
    const uint32_t start = analysis->writeIndex - FV_PITCH_ANALYSIS_WINDOW;
    float energy = 0.0f;
    for (uint32_t i = 0; i < FV_PITCH_ANALYSIS_WINDOW; i++) {
        float sample = analysis->history[(start + i) & mask];
        energy += sample * sample;
    }
    if (energy < 0.01f) {
        return;
    }

    const uint32_t minLag = (uint32_t)fmaxf(2.0f, floorf(chain->pitchAnalysisRate / 350.0f));
    const uint32_t maxLag = (uint32_t)fminf(FV_PITCH_ANALYSIS_MAX_LAG, ceilf(chain->pitchAnalysisRate / 65.0f));
    float normalizedDifference[FV_PITCH_ANALYSIS_MAX_LAG + 1];
    float accumulatedDifference = 0.0f;
    normalizedDifference[0] = 1.0f;
    for (uint32_t lag = 1; lag <= maxLag; lag++) {
        float difference = 0.0f;
        for (uint32_t i = 0; i < FV_PITCH_ANALYSIS_WINDOW; i++) {
            float delta = analysis->history[(start + i) & mask] - analysis->history[(start + i - lag) & mask];
            difference += delta * delta;
        }
        accumulatedDifference += difference;
        normalizedDifference[lag] = accumulatedDifference > 1e-6f ? difference * (float)lag / accumulatedDifference : 1.0f;
    }
    // Use the first confident minimum of the normalized difference to avoid period multiples.
    for (uint32_t lag = minLag; lag < maxLag; lag++) {
        float left = normalizedDifference[lag - 1];
        float middle = normalizedDifference[lag];
        float right = normalizedDifference[lag + 1];
        if (middle < 0.18f && middle < left && middle <= right) {
            float period = (float)lag + 0.5f * (left - right) / (left - 2.0f * middle + right);
            float pitchHz = chain->pitchAnalysisRate / period;
            float correction = fv_clampf(0.8f * 12.0f * log2f(chain->params.referencePitchHz / pitchHz), -7.0f, 7.0f);
            // Move the speaker's average pitch, leaving syllable-to-syllable changes intact.
            analysis->goalSemitones += (correction - analysis->goalSemitones) * (analysis->hasEstimate ? 0.06f : 1.0f);
            analysis->hasEstimate = true;
            return;
        }
    }
}

static inline void fv_pitch_analysis_feed(ForkVoiceChain *chain, float sample) {
    FVPitchAnalysis *analysis = &chain->pitchAnalysis;
    analysis->decimationSum += sample;
    analysis->decimationCount += 1;
    if (analysis->decimationCount == chain->pitchAnalysisDecimation) {
        analysis->history[analysis->writeIndex] = analysis->decimationSum / (float)chain->pitchAnalysisDecimation;
        analysis->writeIndex = (analysis->writeIndex + 1) & (FV_PITCH_ANALYSIS_HISTORY - 1);
        analysis->decimationSum = 0.0f;
        analysis->decimationCount = 0;
        analysis->samplesUntilEstimate -= 1;
        if (analysis->samplesUntilEstimate == 0) {
            fv_pitch_analysis_estimate(chain);
            analysis->samplesUntilEstimate = FV_PITCH_ANALYSIS_HISTORY;
        }
    }
}

static void fv_chain_update_pitch_control(ForkVoiceChain *chain) {
    const ForkVoiceParams *p = &chain->params;
    float semitones = p->pitchSemitones;
    if (p->referencePitchHz > 0.0f) {
        FVPitchAnalysis *analysis = &chain->pitchAnalysis;
        analysis->shiftSemitones += (analysis->goalSemitones - analysis->shiftSemitones) * chain->pitchAnalysisSmoothing;
        semitones += analysis->shiftSemitones;
    }
    if (p->vibratoDepth > 0.001f && p->vibratoRateHz > 0.01f) {
        chain->vibratoPhase = fv_wrap_phase(chain->vibratoPhase + chain->vibratoIncrement);
        semitones += p->vibratoDepth * fv_chain_sine(chain, chain->vibratoPhase);
    }
    if (p->jitter > 0.001f) {
        chain->jitterCounter += 1;
        if (chain->jitterCounter >= chain->jitterPeriod) {
            chain->jitterCounter = 0;
            chain->jitterTarget = fv_random_bipolar(&chain->rng) * 0.7f * p->jitter;
        }
        chain->jitterValue += (chain->jitterTarget - chain->jitterValue) * 0.08f;
        semitones += chain->jitterValue;
    }
    chain->pitchRatio = exp2f(semitones / 12.0f);
}

static inline float fv_chain_pitch(ForkVoiceChain *chain, float x) {
    float *buffer = chain->pitchBuffer;
    uint32_t mask = chain->pitchMask;
    buffer[chain->pitchWrite] = x;
    chain->pitchWrite = (chain->pitchWrite + 1) & mask;

    float window = chain->pitchWindow;
    float phase = chain->pitchPhase + (1.0f - chain->pitchRatio) / window;
    phase = fv_wrap_phase(phase);
    chain->pitchPhase = phase;
    float phase2 = phase + 0.5f;
    if (phase2 >= 1.0f) {
        phase2 -= 1.0f;
    }
    // sin²(πp) + sin²(π(p + ½)) = 1: the taps fade out exactly where their delay wraps.
    float s1 = fv_chain_sine(chain, phase * 0.5f);
    float s2 = fv_chain_sine(chain, phase2 * 0.5f);
    float g1 = s1 * s1;
    float g2 = s2 * s2;
    float y1 = fv_delay_read(buffer, mask, chain->pitchWrite, phase * window);
    float y2 = fv_delay_read(buffer, mask, chain->pitchWrite, phase2 * window);
    return y1 * g1 + y2 * g2;
}

static void fv_chain_process_mono(ForkVoiceChain *chain, float *samples, size_t frames) {
    const ForkVoiceParams *p = &chain->params;
    for (size_t i = 0; i < frames; i++) {
        float dry = samples[i];
        float x = dry;

        if (chain->pitchActive) {
            if (p->referencePitchHz > 0.0f) {
                fv_pitch_analysis_feed(chain, dry);
            }
            if (chain->controlCounter == 0) {
                fv_chain_update_pitch_control(chain);
            }
            chain->controlCounter = (chain->controlCounter + 1) % FV_CONTROL_INTERVAL;
            x = fv_chain_pitch(chain, x);
        }
        if (chain->timbreActive) {
            x = fv_biquad_run(&chain->timbreHigh, fv_biquad_run(&chain->timbreLow, x));
        }
        if (chain->eqActive) {
            x = fv_biquad_run(&chain->eqHigh, fv_biquad_run(&chain->eqMid, fv_biquad_run(&chain->eqLow, x)));
        }
        if (chain->phoneActive) {
            float band = fv_biquad_run(&chain->phoneLow, fv_biquad_run(&chain->phoneHigh, x));
            x = x + (band * 1.4f - x) * p->telephone;
        }
        if (p->distortion > 0.001f) {
            float saturated = fv_fast_tanh(x * chain->distortionDrive) * chain->distortionNorm;
            x = x + (saturated - x) * p->distortion;
        }
        if (p->bitcrushBits < 15.99f) {
            x = floorf(x * chain->bitcrushLevels + 0.5f) / chain->bitcrushLevels;
        }
        if (chain->ringActive) {
            chain->ringPhase = fv_wrap_phase(chain->ringPhase + chain->ringIncrement);
            float modulated = x * fv_chain_sine(chain, chain->ringPhase);
            x = x + (modulated - x) * p->ringModMix;
        }
        if (chain->chorusBuffer != NULL) {
            chain->chorusBuffer[chain->chorusWrite] = x;
            chain->chorusWrite = (chain->chorusWrite + 1) & chain->chorusMask;
            chain->chorusPhase = fv_wrap_phase(chain->chorusPhase + chain->chorusIncrement);
            float delay = chain->chorusBase + chain->chorusDepth * fv_chain_sine(chain, chain->chorusPhase);
            float delayed = fv_delay_read(chain->chorusBuffer, chain->chorusMask, chain->chorusWrite, delay);
            x = x * (1.0f - 0.4f * p->chorus) + delayed * 0.6f * p->chorus;
        }
        if (chain->flangerBuffer != NULL) {
            chain->flangerPhase = fv_wrap_phase(chain->flangerPhase + chain->flangerIncrement);
            float delay = chain->flangerBase + chain->flangerDepth * fv_chain_sine(chain, chain->flangerPhase);
            float delayed = fv_delay_read(chain->flangerBuffer, chain->flangerMask, chain->flangerWrite, delay);
            chain->flangerBuffer[chain->flangerWrite] = x + delayed * 0.55f * p->flanger;
            chain->flangerWrite = (chain->flangerWrite + 1) & chain->flangerMask;
            x = (x + delayed * p->flanger) / (1.0f + 0.5f * p->flanger);
        }
        if (chain->echoBuffer != NULL) {
            uint32_t readIndex = (chain->echoWrite - chain->echoDelay) & chain->echoMask;
            float delayed = chain->echoBuffer[readIndex];
            chain->echoBuffer[chain->echoWrite] = x + delayed * p->echoFeedback;
            chain->echoWrite = (chain->echoWrite + 1) & chain->echoMask;
            x = x + delayed * p->echoMix;
        }
        if (chain->combBuffers[0] != NULL) {
            float input = x * 0.3f;
            float sum = 0.0f;
            for (int c = 0; c < 4; c++) {
                float *buffer = chain->combBuffers[c];
                uint32_t index = chain->combIndex[c];
                float output = buffer[index];
                chain->combStore[c] = output * (1.0f - chain->combDamp) + chain->combStore[c] * chain->combDamp;
                buffer[index] = input + chain->combStore[c] * chain->combFeedback;
                index += 1;
                if (index >= chain->combLength[c]) {
                    index = 0;
                }
                chain->combIndex[c] = index;
                sum += output;
            }
            float reverb = sum * 0.25f;
            for (int a = 0; a < 2; a++) {
                float *buffer = chain->allpassBuffers[a];
                uint32_t index = chain->allpassIndex[a];
                float buffered = buffer[index];
                float output = buffered - reverb;
                buffer[index] = reverb + buffered * 0.5f;
                index += 1;
                if (index >= chain->allpassLength[a]) {
                    index = 0;
                }
                chain->allpassIndex[a] = index;
                reverb = output;
            }
            x = x + reverb * p->reverbMix * 1.5f;
        }
        if (p->breathiness > 0.001f) {
            float level = fabsf(x);
            chain->breathEnvelope = level > chain->breathEnvelope ? level : chain->breathEnvelope * chain->breathRelease;
            float noise = fv_random_bipolar(&chain->rng);
            chain->breathHighPass = chain->breathCoefficient * (chain->breathHighPass + noise - chain->breathPreviousNoise);
            chain->breathPreviousNoise = noise;
            x += chain->breathHighPass * chain->breathEnvelope * p->breathiness * 0.6f;
        }
        if (chain->compressorActive) {
            float level = fabsf(x);
            float coefficient = level > chain->compressorEnvelope ? chain->compressorAttack : chain->compressorRelease;
            chain->compressorEnvelope += (level - chain->compressorEnvelope) * coefficient;
            if (chain->compressorCounter == 0) {
                float envelopeDb = 20.0f * log10f(chain->compressorEnvelope + 1e-6f);
                float over = envelopeDb - chain->compressorThresholdDb;
                float gainDb = chain->compressorMakeupDb;
                if (over > 0.0f) {
                    gainDb -= over * (1.0f - 1.0f / chain->compressorRatio);
                }
                chain->compressorTargetGain = powf(10.0f, gainDb / 20.0f);
            }
            chain->compressorCounter = (chain->compressorCounter + 1) % 16;
            chain->compressorGain += (chain->compressorTargetGain - chain->compressorGain) * 0.01f;
            x *= chain->compressorGain;
        }
        x *= chain->gainLinear;
        if (p->wet < 0.999f) {
            x = dry + (x - dry) * p->wet;
        }
        samples[i] = fv_soft_limit(x);
    }
}

static void fv_chain_prepare(ForkVoiceChain *chain, uint32_t sampleRate) {
    if (sampleRate == 0) {
        sampleRate = 48000;
    }
    if (chain->sampleRate != sampleRate) {
        fv_chain_configure(chain, sampleRate);
    }
}

void ForkVoiceChainPrepare(ForkVoiceChain *chain, uint32_t sampleRate) {
    fv_chain_prepare(chain, sampleRate);
}

void ForkVoiceChainProcessFloat(ForkVoiceChain *chain, float *samples, size_t frames, size_t channels, uint32_t sampleRate) {
    if (frames == 0 || channels == 0) {
        return;
    }
    fv_chain_prepare(chain, sampleRate);
    if (channels == 1) {
        fv_chain_process_mono(chain, samples, frames);
        return;
    }
    size_t offset = 0;
    while (offset < frames) {
        size_t count = frames - offset;
        if (count > FV_BLOCK_FRAMES) {
            count = FV_BLOCK_FRAMES;
        }
        float scale = 1.0f / (float)channels;
        for (size_t i = 0; i < count; i++) {
            const float *frame = samples + (offset + i) * channels;
            float sum = 0.0f;
            for (size_t c = 0; c < channels; c++) {
                sum += frame[c];
            }
            chain->scratch[i] = sum * scale;
        }
        fv_chain_process_mono(chain, chain->scratch, count);
        for (size_t i = 0; i < count; i++) {
            float *frame = samples + (offset + i) * channels;
            for (size_t c = 0; c < channels; c++) {
                frame[c] = chain->scratch[i];
            }
        }
        offset += count;
    }
}

void ForkVoiceChainProcessInt16(ForkVoiceChain *chain, int16_t *samples, size_t frames, size_t channels, uint32_t sampleRate) {
    if (frames == 0 || channels == 0) {
        return;
    }
    fv_chain_prepare(chain, sampleRate);
    size_t offset = 0;
    const float scale = 1.0f / 32768.0f;
    while (offset < frames) {
        size_t count = frames - offset;
        if (count > FV_BLOCK_FRAMES) {
            count = FV_BLOCK_FRAMES;
        }
        float channelScale = scale / (float)channels;
        for (size_t i = 0; i < count; i++) {
            const int16_t *frame = samples + (offset + i) * channels;
            float sum = 0.0f;
            for (size_t c = 0; c < channels; c++) {
                sum += (float)frame[c];
            }
            chain->scratch[i] = sum * channelScale;
        }
        fv_chain_process_mono(chain, chain->scratch, count);
        for (size_t i = 0; i < count; i++) {
            int16_t value = fv_float_to_int16(chain->scratch[i]);
            int16_t *frame = samples + (offset + i) * channels;
            for (size_t c = 0; c < channels; c++) {
                frame[c] = value;
            }
        }
        offset += count;
    }
}

void ForkVoiceChainCallProcess(void *context, int16_t *samples, size_t frames, size_t channels, uint32_t sampleRate) {
    if (context == NULL) {
        return;
    }
    ForkVoiceChainProcessInt16((ForkVoiceChain *)context, samples, frames, channels, sampleRate);
}

void ForkVoiceChainCallRelease(void *context) {
    ForkVoiceChainDestroy((ForkVoiceChain *)context);
}

// MARK: - Playback equalizer

static const float fv_eq_frequencies[ForkAudioEqualizerBandCount] = { 60.0f, 230.0f, 910.0f, 3600.0f, 14000.0f };

// Seqlock: the writer (control side, serialized by the mutex) makes the counter odd while it writes.
static _Atomic uint32_t fv_eq_sequence = 0;
static _Atomic float fv_eq_gains[ForkAudioEqualizerBandCount];
static _Atomic bool fv_eq_kinds[3];
static pthread_mutex_t fv_eq_writer_lock = PTHREAD_MUTEX_INITIALIZER;

float ForkAudioEqualizerBandFrequency(int band) {
    if (band < 0 || band >= ForkAudioEqualizerBandCount) {
        return 0.0f;
    }
    return fv_eq_frequencies[band];
}

void ForkAudioEqualizerSetParameters(const float *gainsDb, bool audio, bool roundVideo, bool video) {
    pthread_mutex_lock(&fv_eq_writer_lock);
    atomic_fetch_add_explicit(&fv_eq_sequence, 1, memory_order_acq_rel);
    for (int i = 0; i < ForkAudioEqualizerBandCount; i++) {
        atomic_store_explicit(&fv_eq_gains[i], fv_clampf(gainsDb[i], -12.0f, 12.0f), memory_order_relaxed);
    }
    atomic_store_explicit(&fv_eq_kinds[ForkAudioEqualizerKindAudio], audio, memory_order_relaxed);
    atomic_store_explicit(&fv_eq_kinds[ForkAudioEqualizerKindRoundVideo], roundVideo, memory_order_relaxed);
    atomic_store_explicit(&fv_eq_kinds[ForkAudioEqualizerKindVideo], video, memory_order_relaxed);
    atomic_fetch_add_explicit(&fv_eq_sequence, 1, memory_order_release);
    pthread_mutex_unlock(&fv_eq_writer_lock);
}

/// Reads a consistent copy; false if the writer kept it busy (the caller keeps what it had).
static bool fv_eq_snapshot(float *gains, bool *kinds, uint32_t *sequence) {
    for (int attempt = 0; attempt < 8; attempt++) {
        uint32_t before = atomic_load_explicit(&fv_eq_sequence, memory_order_acquire);
        if ((before & 1u) != 0) {
            continue;
        }
        for (int i = 0; i < ForkAudioEqualizerBandCount; i++) {
            gains[i] = atomic_load_explicit(&fv_eq_gains[i], memory_order_relaxed);
        }
        for (int i = 0; i < 3; i++) {
            kinds[i] = atomic_load_explicit(&fv_eq_kinds[i], memory_order_relaxed);
        }
        atomic_thread_fence(memory_order_acquire);
        uint32_t after = atomic_load_explicit(&fv_eq_sequence, memory_order_relaxed);
        if (before == after) {
            *sequence = before;
            return true;
        }
    }
    return false;
}

static bool fv_eq_has_gain(const float *gains) {
    for (int i = 0; i < ForkAudioEqualizerBandCount; i++) {
        if (fabsf(gains[i]) > 0.05f) {
            return true;
        }
    }
    return false;
}

bool ForkAudioEqualizerIsActiveForKind(ForkAudioEqualizerKind kind) {
    if ((int)kind < 0 || (int)kind > 2) {
        return false;
    }
    if (!atomic_load_explicit(&fv_eq_kinds[kind], memory_order_relaxed)) {
        return false;
    }
    for (int i = 0; i < ForkAudioEqualizerBandCount; i++) {
        if (fabsf(atomic_load_explicit(&fv_eq_gains[i], memory_order_relaxed)) > 0.05f) {
            return true;
        }
    }
    return false;
}

struct ForkAudioEqualizer {
    ForkAudioEqualizerKind kind;
    uint32_t sequence;
    bool hasSnapshot;
    uint32_t sampleRate;
    bool active;
    float gains[ForkAudioEqualizerBandCount];
    float preamp;
    FVBiquad coefficients[ForkAudioEqualizerBandCount];
    float state[FV_MAX_CHANNELS][ForkAudioEqualizerBandCount][2];
};

ForkAudioEqualizer *ForkAudioEqualizerCreate(ForkAudioEqualizerKind kind) {
    ForkAudioEqualizer *equalizer = (ForkAudioEqualizer *)calloc(1, sizeof(ForkAudioEqualizer));
    if (equalizer == NULL) {
        return NULL;
    }
    equalizer->kind = kind;
    equalizer->preamp = 1.0f;
    for (int i = 0; i < ForkAudioEqualizerBandCount; i++) {
        fv_biquad_identity(&equalizer->coefficients[i]);
    }
    return equalizer;
}

void ForkAudioEqualizerDestroy(ForkAudioEqualizer *equalizer) {
    free(equalizer);
}

static void fv_eq_compute(const float *gains, float sampleRate, FVBiquad *coefficients, float *preamp) {
    float maxBoost = 0.0f;
    for (int i = 0; i < ForkAudioEqualizerBandCount; i++) {
        float gain = gains[i];
        if (gain > maxBoost) {
            maxBoost = gain;
        }
        if (fabsf(gain) <= 0.05f) {
            fv_biquad_identity(&coefficients[i]);
        } else if (i == 0) {
            fv_biquad_low_shelf(&coefficients[i], sampleRate, fv_eq_frequencies[i], gain);
        } else if (i == ForkAudioEqualizerBandCount - 1) {
            fv_biquad_high_shelf(&coefficients[i], sampleRate, fv_eq_frequencies[i], gain);
        } else {
            fv_biquad_peak(&coefficients[i], sampleRate, fv_eq_frequencies[i], 1.0f, gain);
        }
    }
    // Half of the strongest boost as headroom: boosted bands do not clip the rest.
    *preamp = powf(10.0f, -0.5f * maxBoost / 20.0f);
}

/// Picks up a new parameter set or sample rate. The filter states are kept: no click on a change.
static void fv_eq_refresh(ForkAudioEqualizer *equalizer, uint32_t sampleRate) {
    uint32_t current = atomic_load_explicit(&fv_eq_sequence, memory_order_acquire);
    if (equalizer->hasSnapshot && current == equalizer->sequence && sampleRate == equalizer->sampleRate) {
        return;
    }
    float gains[ForkAudioEqualizerBandCount];
    bool kinds[3];
    uint32_t sequence = 0;
    if (!fv_eq_snapshot(gains, kinds, &sequence)) {
        return;
    }
    bool wasActive = equalizer->active;
    equalizer->hasSnapshot = true;
    equalizer->sequence = sequence;
    equalizer->sampleRate = sampleRate;
    equalizer->active = kinds[equalizer->kind] && fv_eq_has_gain(gains);
    memcpy(equalizer->gains, gains, sizeof(gains));
    if (equalizer->active) {
        fv_eq_compute(gains, (float)sampleRate, equalizer->coefficients, &equalizer->preamp);
        if (!wasActive) {
            memset(equalizer->state, 0, sizeof(equalizer->state));
        }
    }
}

static inline float fv_eq_run(ForkAudioEqualizer *equalizer, size_t channel, float x) {
    x *= equalizer->preamp;
    for (int b = 0; b < ForkAudioEqualizerBandCount; b++) {
        const FVBiquad *f = &equalizer->coefficients[b];
        float *z = equalizer->state[channel][b];
        float y = f->b0 * x + z[0];
        z[0] = f->b1 * x - f->a1 * y + z[1];
        z[1] = f->b2 * x - f->a2 * y;
        x = y;
    }
    return x;
}

void ForkAudioEqualizerProcessInt16(ForkAudioEqualizer *equalizer, int16_t *samples, size_t frames, size_t channels, uint32_t sampleRate) {
    if (frames == 0 || channels == 0 || sampleRate == 0) {
        return;
    }
    fv_eq_refresh(equalizer, sampleRate);
    if (!equalizer->active) {
        return;
    }
    size_t processedChannels = channels > FV_MAX_CHANNELS ? FV_MAX_CHANNELS : channels;
    const float scale = 1.0f / 32768.0f;
    for (size_t i = 0; i < frames; i++) {
        int16_t *frame = samples + i * channels;
        for (size_t c = 0; c < processedChannels; c++) {
            // Limited like the Float path: at a large boost a plain clamp to Int16 squared off the peaks.
            frame[c] = fv_float_to_int16(fv_soft_limit(fv_eq_run(equalizer, c, (float)frame[c] * scale)));
        }
    }
}

void ForkAudioEqualizerProcessFloat(ForkAudioEqualizer *equalizer, float *samples, size_t frames, size_t channels, uint32_t sampleRate) {
    if (frames == 0 || channels == 0 || sampleRate == 0) {
        return;
    }
    fv_eq_refresh(equalizer, sampleRate);
    if (!equalizer->active) {
        return;
    }
    size_t processedChannels = channels > FV_MAX_CHANNELS ? FV_MAX_CHANNELS : channels;
    for (size_t i = 0; i < frames; i++) {
        float *frame = samples + i * channels;
        for (size_t c = 0; c < processedChannels; c++) {
            frame[c] = fv_soft_limit(fv_eq_run(equalizer, c, frame[c]));
        }
    }
}

void ForkAudioEqualizerProcessOffline(const float *gainsDb, float *samples, size_t frames, uint32_t sampleRate) {
    if (frames == 0 || sampleRate == 0) {
        return;
    }
    float gains[ForkAudioEqualizerBandCount];
    for (int i = 0; i < ForkAudioEqualizerBandCount; i++) {
        gains[i] = fv_clampf(gainsDb[i], -12.0f, 12.0f);
    }
    if (!fv_eq_has_gain(gains)) {
        return;
    }
    ForkAudioEqualizer equalizer;
    memset(&equalizer, 0, sizeof(equalizer));
    equalizer.active = true;
    fv_eq_compute(gains, (float)sampleRate, equalizer.coefficients, &equalizer.preamp);
    for (size_t i = 0; i < frames; i++) {
        samples[i] = fv_soft_limit(fv_eq_run(&equalizer, 0, samples[i]));
    }
}
