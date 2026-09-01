// Empty shim: doomgeneric's i_sound.c includes <SDL_mixer.h> under FEATURE_SOUND,
// but uses no Mix_* symbols (they appear only in comments). This file lets us
// enable FEATURE_SOUND without patching the vendored engine.
#ifndef DOOM4OH_SDL_MIXER_SHIM_H
#define DOOM4OH_SDL_MIXER_SHIM_H
#endif
