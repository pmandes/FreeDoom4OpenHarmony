#include "ohos_audio.h"

#include <atomic>
#include <chrono>
#include <cstring>

#include <ohaudio/native_audiorenderer.h>
#include <ohaudio/native_audiostreambuilder.h>

#include "hilog/log.h"

#undef LOG_TAG
#define LOG_TAG "Doom4OH"

namespace audio {
namespace {

OH_AudioRenderer *g_renderer = nullptr;
RenderCallback g_callback = nullptr;
std::atomic<uint32_t> g_cbCount{0};
std::atomic<bool> g_userPaused{false}; // pause from lifecycle (Home/background) — takes priority over resume from an interruption

std::atomic<int64_t> g_maxMixUs{0};

OH_AudioData_Callback_Result OnWriteData(OH_AudioRenderer *renderer, void *userData, void *data, int32_t size)
{
    auto *frames = static_cast<int16_t *>(data);
    const int32_t frameCount = size / (kChannels * static_cast<int32_t>(sizeof(int16_t)));

    const auto t0 = std::chrono::steady_clock::now();
    if (g_callback != nullptr) {
        g_callback(frames, frameCount);
    } else {
        std::memset(data, 0, static_cast<size_t>(size));
    }
    const auto mixUs =
        std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now() - t0).count();

    // Underrun diagnostics: time budget = frameCount/44100 s (93 ms at 4096).
    int64_t prevMax = g_maxMixUs.load(std::memory_order_relaxed);
    while (mixUs > prevMax && !g_maxMixUs.compare_exchange_weak(prevMax, mixUs, std::memory_order_relaxed)) {
    }
    const int64_t budgetUs = static_cast<int64_t>(frameCount) * 1000000 / kSampleRate;
    if (mixUs > budgetUs / 2) {
        OH_LOG_WARN(LOG_APP, "audio: slow mix %{public}lld us (budget %{public}lld us)",
                    static_cast<long long>(mixUs), static_cast<long long>(budgetUs));
    }

    const uint32_t n = g_cbCount.fetch_add(1, std::memory_order_relaxed);
    if (n == 0) {
        OH_LOG_INFO(LOG_APP, "audio: first callback, %{public}d B (%{public}d frames)", size, frameCount);
    } else if (n % 2000 == 0) {
        OH_LOG_INFO(LOG_APP, "audio: %{public}u callbacks, max mix %{public}lld us",
                    n, static_cast<long long>(g_maxMixUs.exchange(0, std::memory_order_relaxed)));
    }
    return AUDIO_DATA_CALLBACK_RESULT_VALID;
}

// Audio focus interruptions (call, assistant, another app).
// On FORCE the system pauses/ducks the stream itself — we keep our state
// consistent and resume on HINT_RESUME, provided the game isn't paused from lifecycle.
void OnInterrupt(OH_AudioRenderer *renderer, void *userData, OH_AudioInterrupt_ForceType type,
                 OH_AudioInterrupt_Hint hint)
{
    OH_LOG_INFO(LOG_APP, "audio: interrupt force=%{public}d hint=%{public}d", type, hint);
    switch (hint) {
        case AUDIOSTREAM_INTERRUPT_HINT_PAUSE:
        case AUDIOSTREAM_INTERRUPT_HINT_STOP:
            if (g_renderer != nullptr) {
                OH_AudioRenderer_Pause(g_renderer);
            }
            break;
        case AUDIOSTREAM_INTERRUPT_HINT_RESUME:
            if (g_renderer != nullptr && !g_userPaused.load(std::memory_order_acquire)) {
                OH_AudioRenderer_Start(g_renderer);
            }
            break;
        default:
            break; // DUCK/UNDUCK/MUTE handled by the system on FORCE
    }
}

void OnError(OH_AudioRenderer *renderer, void *userData, OH_AudioStream_Result error)
{
    OH_LOG_ERROR(LOG_APP, "audio: renderer error %{public}d — attempting stream restart", error);
    if (g_renderer != nullptr && !g_userPaused.load(std::memory_order_acquire)) {
        const OH_AudioStream_Result res = OH_AudioRenderer_Start(g_renderer);
        if (res != AUDIOSTREAM_SUCCESS) {
            OH_LOG_ERROR(LOG_APP, "audio: restart failed (%{public}d) — game continues without sound", res);
        }
    }
}

} // namespace

bool Start(RenderCallback cb)
{
    if (g_renderer != nullptr) {
        return true;
    }
    g_callback = cb;

    OH_AudioStreamBuilder *builder = nullptr;
    if (OH_AudioStreamBuilder_Create(&builder, AUDIOSTREAM_TYPE_RENDERER) != AUDIOSTREAM_SUCCESS) {
        OH_LOG_ERROR(LOG_APP, "audio: builder create failed");
        return false;
    }
    OH_AudioStreamBuilder_SetSamplingRate(builder, kSampleRate);
    OH_AudioStreamBuilder_SetChannelCount(builder, kChannels);
    OH_AudioStreamBuilder_SetSampleFormat(builder, AUDIOSTREAM_SAMPLE_S16LE);
    OH_AudioStreamBuilder_SetLatencyMode(builder, AUDIOSTREAM_LATENCY_MODE_NORMAL);
    OH_AudioStreamBuilder_SetRendererInfo(builder, AUDIOSTREAM_USAGE_GAME);
    OH_AudioStreamBuilder_SetRendererWriteDataCallback(builder, OnWriteData, nullptr);
    OH_AudioStreamBuilder_SetRendererInterruptCallback(builder, OnInterrupt, nullptr);
    OH_AudioStreamBuilder_SetRendererErrorCallback(builder, OnError, nullptr);

    const OH_AudioStream_Result res = OH_AudioStreamBuilder_GenerateRenderer(builder, &g_renderer);
    OH_AudioStreamBuilder_Destroy(builder);
    if (res != AUDIOSTREAM_SUCCESS || g_renderer == nullptr) {
        OH_LOG_ERROR(LOG_APP, "audio: GenerateRenderer failed: %{public}d", res);
        g_renderer = nullptr;
        return false;
    }
    if (OH_AudioRenderer_Start(g_renderer) != AUDIOSTREAM_SUCCESS) {
        OH_LOG_ERROR(LOG_APP, "audio: renderer start failed");
        OH_AudioRenderer_Release(g_renderer);
        g_renderer = nullptr;
        return false;
    }
    OH_LOG_INFO(LOG_APP, "audio: renderer started (%{public}d Hz, %{public}d ch, S16LE)", kSampleRate, kChannels);
    return true;
}

void Stop()
{
    if (g_renderer != nullptr) {
        OH_AudioRenderer_Stop(g_renderer);
        OH_AudioRenderer_Release(g_renderer);
        g_renderer = nullptr;
        OH_LOG_INFO(LOG_APP, "audio: renderer stopped");
    }
}

void Pause()
{
    g_userPaused.store(true, std::memory_order_release);
    if (g_renderer != nullptr) {
        OH_AudioRenderer_Pause(g_renderer);
    }
}

void Resume()
{
    g_userPaused.store(false, std::memory_order_release);
    if (g_renderer != nullptr) {
        OH_AudioRenderer_Start(g_renderer);
    }
}

} // namespace audio
