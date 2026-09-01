#ifndef DOOM4OH_DOOMGENERIC_OHOS_H
#define DOOM4OH_DOOMGENERIC_OHOS_H

#include <string>

namespace game {

// Starts the game loop on its own thread. workDir becomes the CWD (config/savegame
// land in the sandbox). Returns false if the game is already running.
bool Start(const std::string &wadPath, const std::string &workDir);

// Doom has no clean shutdown (I_Quit calls exit()) — Stop only halts the
// pacing loop after the next tick; used when closing the ability.
void Stop();

bool IsRunning();

// True once the engine tried to exit() (Quit Game menu, or a fatal I_Error). The
// ArkTS side polls this and calls terminateSelf to close the app gracefully —
// calling exit() directly is forbidden on HarmonyOS/OpenHarmony (appspawn aborts it).
bool IsQuitRequested();

// Pauses/resumes the tick loop (background/foreground). Game state is kept.
void Pause();
void Resume();

} // namespace game

#endif // DOOM4OH_DOOMGENERIC_OHOS_H
