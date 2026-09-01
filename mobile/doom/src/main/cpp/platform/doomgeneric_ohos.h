#ifndef DOOM4OH_DOOMGENERIC_OHOS_H
#define DOOM4OH_DOOMGENERIC_OHOS_H

#include <string>

namespace game {

// Starts the game loop on its own thread. workDir becomes the CWD (config/savegame
// land in the sandbox). Returns false if the game is already running.
bool Start(const std::string &wadPath, const std::string &workDir);

// Doom has no clean shutdown (I_Quit calls exit()) — Stop only stops the
// pacing loop after the next tick; used when the ability is closing.
void Stop();

bool IsRunning();

// Pauses/resumes the tick loop (background/foreground). Game state is preserved.
void Pause();
void Resume();

} // namespace game

#endif // DOOM4OH_DOOMGENERIC_OHOS_H
