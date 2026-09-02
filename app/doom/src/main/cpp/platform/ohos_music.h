#ifndef DOOM4OH_OHOS_MUSIC_H
#define DOOM4OH_OHOS_MUSIC_H

#include <cstdint>
#include <string>

namespace music {

// Absolute path to the GM soundfont (.sf2) — set before the game starts.
void SetSoundFontPath(const std::string &path);

// Mixes music additively into the accumulation buffer (stereo int32).
// Called from the audio thread by the SFX mixer; frameCount ≤ 4096.
void MixInto(int32_t *accum, int32_t frameCount);

} // namespace music

#endif // DOOM4OH_OHOS_MUSIC_H
