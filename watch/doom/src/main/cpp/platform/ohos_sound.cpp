// DG_sound_module: SFX via OHAudio.
// The game thread calls Start/Stop/UpdateSoundParams; the audio thread mixes in MixAudio.
// Communication through per-channel atomics — zero locks in the audio path.

#include <algorithm>
#include <atomic>
#include <cstdint>
#include <cstring>
#include <vector>

#include "hilog/log.h"

#include "ohos_audio.h"
#include "ohos_music.h"

extern "C" {
#include "i_sound.h"
#include "deh_str.h"
#include "m_misc.h"
#include "w_wad.h"
#include "z_zone.h"
}

#undef LOG_TAG
#define LOG_TAG "Doom4OH"

// i_sound.c binds these variables to the config (normally i_sdlsound.c defines them,
// which we don't compile). Unused here — we do the resampling ourselves.
extern "C" int use_libsamplerate = 0;
extern "C" float libsamplerate_scale = 0.65f;

namespace {

constexpr int kNumChannels = 16;
constexpr int32_t kMaxChunkFrames = 4096;

struct CachedSound {
    std::vector<int16_t> samples; // mono, audio::kSampleRate
};

struct Channel {
    std::atomic<const CachedSound *> snd{nullptr}; // nullptr = free channel
    std::atomic<uint32_t> pos{0};
    std::atomic<int> leftVol{0};  // 0..127
    std::atomic<int> rightVol{0}; // 0..127
};

Channel g_channels[kNumChannels];
bool g_useSfxPrefix = true;
std::vector<int32_t> g_accum; // mix accumulation buffer (audio thread)

void SetChannelVolume(Channel &ch, int vol, int sep)
{
    // sep 0..254 (128 = center), vol 0..127 — result scaled 0..127 per channel.
    int left = ((254 - sep) * vol) / 254;
    int right = (sep * vol) / 254;
    ch.leftVol.store(std::clamp(left, 0, 127), std::memory_order_relaxed);
    ch.rightVol.store(std::clamp(right, 0, 127), std::memory_order_relaxed);
}

void MixAudio(int16_t *frames, int32_t frameCount)
{
    int32_t done = 0;
    while (done < frameCount) {
        const int32_t n = std::min(frameCount - done, kMaxChunkFrames);
        std::fill(g_accum.begin(), g_accum.begin() + static_cast<size_t>(n) * 2, 0);

        music::MixInto(g_accum.data(), n); // music underneath, SFX on top

        for (Channel &ch : g_channels) {
            const CachedSound *snd = ch.snd.load(std::memory_order_acquire);
            if (snd == nullptr) {
                continue;
            }
            uint32_t pos = ch.pos.load(std::memory_order_relaxed);
            const int lv = ch.leftVol.load(std::memory_order_relaxed);
            const int rv = ch.rightVol.load(std::memory_order_relaxed);
            const int16_t *smp = snd->samples.data();
            const auto len = static_cast<uint32_t>(snd->samples.size());
            for (int32_t i = 0; i < n && pos < len; i++, pos++) {
                const int32_t v = smp[pos];
                g_accum[static_cast<size_t>(2) * i] += (v * lv) >> 7;
                g_accum[static_cast<size_t>(2) * i + 1] += (v * rv) >> 7;
            }
            ch.pos.store(pos, std::memory_order_relaxed);
            if (pos >= len) {
                ch.snd.store(nullptr, std::memory_order_release);
            }
        }

        for (int32_t i = 0; i < n * 2; i++) {
            frames[static_cast<size_t>(done) * 2 + i] =
                static_cast<int16_t>(std::clamp(g_accum[i], -32768, 32767));
        }
        done += n;
    }
}

// Decodes a DMX lump (8-bit unsigned mono) and linearly resamples to 44100/int16.
bool CacheSound(sfxinfo_t *sfx)
{
    const int lumpnum = sfx->lumpnum;
    const auto *data = static_cast<const uint8_t *>(W_CacheLumpNum(lumpnum, PU_STATIC));
    const unsigned lumplen = W_LumpLength(lumpnum);

    if (lumplen < 8 || data[0] != 0x03 || data[1] != 0x00) {
        return false;
    }
    const int samplerate = (data[3] << 8) | data[2];
    const uint32_t length = (static_cast<uint32_t>(data[7]) << 24) | (data[6] << 16) | (data[5] << 8) | data[4];
    // Header lying about the length, or samples shorter than the DMX cut-off — reject.
    if (samplerate <= 0 || length > lumplen - 8 || length <= 48) {
        return false;
    }

    // DMX skips the first 16 and last 16 sample bytes.
    const uint8_t *samples = data + 8 + 16;
    const uint32_t usable = length - 32;

    const auto outLen =
        static_cast<uint32_t>(static_cast<uint64_t>(usable) * audio::kSampleRate / static_cast<uint32_t>(samplerate));
    auto *cached = new CachedSound();
    cached->samples.resize(outLen);

    const uint64_t step = (static_cast<uint64_t>(samplerate) << 16) / audio::kSampleRate; // 16.16 fixed point
    uint64_t srcPos = 0;
    for (uint32_t i = 0; i < outLen; i++, srcPos += step) {
        const uint32_t idx = static_cast<uint32_t>(srcPos >> 16);
        const uint32_t frac = static_cast<uint32_t>(srcPos & 0xFFFF);
        const int32_t s0 = samples[std::min(idx, usable - 1)];
        const int32_t s1 = samples[std::min(idx + 1, usable - 1)];
        const int32_t v8 = s0 + static_cast<int32_t>(((s1 - s0) * static_cast<int32_t>(frac)) >> 16);
        cached->samples[i] = static_cast<int16_t>((v8 - 128) << 8);
    }

    sfx->driver_data = cached;
    W_ReleaseLumpNum(lumpnum);
    return true;
}

boolean I_OHOS_InitSound(boolean use_sfx_prefix)
{
    g_useSfxPrefix = use_sfx_prefix != 0;
    g_accum.resize(static_cast<size_t>(kMaxChunkFrames) * 2);
    if (!audio::Start(MixAudio)) {
        return false;
    }
    OH_LOG_INFO(LOG_APP, "sound: OHOS sfx module initialized");
    return true;
}

void I_OHOS_ShutdownSound(void)
{
    audio::Stop();
}

int I_OHOS_GetSfxLumpNum(sfxinfo_t *sfx)
{
    if (sfx->link != nullptr) {
        sfx = sfx->link;
    }
    char namebuf[9];
    if (g_useSfxPrefix) {
        M_snprintf(namebuf, sizeof(namebuf), "ds%s", DEH_String(sfx->name));
    } else {
        M_StringCopy(namebuf, DEH_String(sfx->name), sizeof(namebuf));
    }
    return W_GetNumForName(namebuf);
}

void I_OHOS_UpdateSound(void) {}

void I_OHOS_UpdateSoundParams(int channel, int vol, int sep)
{
    if (channel >= 0 && channel < kNumChannels) {
        SetChannelVolume(g_channels[channel], vol, sep);
    }
}

int I_OHOS_StartSound(sfxinfo_t *sfx, int channel, int vol, int sep)
{
    if (channel < 0 || channel >= kNumChannels) {
        return -1;
    }
    if (sfx->driver_data == nullptr && !CacheSound(sfx)) {
        return -1;
    }
    Channel &ch = g_channels[channel];
    ch.snd.store(nullptr, std::memory_order_release); // stop whatever was playing
    SetChannelVolume(ch, vol, sep);
    ch.pos.store(0, std::memory_order_relaxed);
    ch.snd.store(static_cast<const CachedSound *>(sfx->driver_data), std::memory_order_release);

    static std::atomic<bool> firstStart{true};
    if (firstStart.exchange(false, std::memory_order_relaxed)) {
        OH_LOG_INFO(LOG_APP, "sound: first sfx '%{public}s' on channel %{public}d", sfx->name, channel);
    }
    return channel;
}

void I_OHOS_StopSound(int channel)
{
    if (channel >= 0 && channel < kNumChannels) {
        g_channels[channel].snd.store(nullptr, std::memory_order_release);
    }
}

boolean I_OHOS_SoundIsPlaying(int channel)
{
    if (channel < 0 || channel >= kNumChannels) {
        return false;
    }
    return g_channels[channel].snd.load(std::memory_order_acquire) != nullptr;
}

// We cache lazily on the first StartSound — prefetching is unnecessary.
void I_OHOS_CacheSounds(sfxinfo_t *sounds, int num_sounds) {}

snddevice_t g_soundDevices[] = {SNDDEVICE_SB};

} // namespace

extern "C" sound_module_t DG_sound_module = {
    g_soundDevices,
    1,
    I_OHOS_InitSound,
    I_OHOS_ShutdownSound,
    I_OHOS_GetSfxLumpNum,
    I_OHOS_UpdateSound,
    I_OHOS_UpdateSoundParams,
    I_OHOS_StartSound,
    I_OHOS_StopSound,
    I_OHOS_SoundIsPlaying,
    I_OHOS_CacheSounds,
};
