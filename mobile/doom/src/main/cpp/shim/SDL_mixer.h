// Empty shim: doomgeneric's i_sound.c includes <SDL_mixer.h> under FEATURE_SOUND,
// but does not use any Mix_* symbols (they only appear in comments). This file
// lets FEATURE_SOUND be enabled without patching the vendored engine.
#ifndef DOOM4OH_SDL_MIXER_SHIM_H
#define DOOM4OH_SDL_MIXER_SHIM_H
#endif
