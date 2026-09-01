#ifndef DOOM4OH_OHOS_AUDIO_H
#define DOOM4OH_OHOS_AUDIO_H

#include <cstdint>

namespace audio {

constexpr int kSampleRate = 44100;
constexpr int kChannels = 2; // stereo interleaved L,R

// Mixing callback: fills frameCount stereo S16 frames.
// Called from the OHAudio audio thread — no locks or allocations inside.
using RenderCallback = void (*)(int16_t *frames, int32_t frameCount);

// Creates the OHAudio renderer (44100/stereo/S16, usage GAME) and starts the stream.
// Returns false when audio is unavailable — the game then runs silently.
bool Start(RenderCallback cb);

void Stop();

// Pause/resume the stream (tied to game::Pause/Resume).
void Pause();
void Resume();

} // namespace audio

#endif // DOOM4OH_OHOS_AUDIO_H
