// DG_music_module: MUS/MIDI -> FluidLite (a glib-free FluidSynth core) rendering a
// SoundFont from the sandbox. FluidLite adds the reverb/chorus and full SF2 modulator
// engine that TinySoundFont lacks, so an SC-55 SoundFont sounds much closer to the
// Roland module DOOM's music was written for.
//
// The game thread calls Register/Play/Stop/SetVolume under a mutex; the audio thread
// renders in MixInto via try_lock (on a song change — one tick of music silence).

#include <algorithm>
#include <cstdint>
#include <cstring>
#include <mutex>
#include <string>
#include <vector>

#include "hilog/log.h"

#include "ohos_audio.h"
#include "ohos_music.h"

#include "fluidlite.h"

#define TML_IMPLEMENTATION
#include "tml.h"

extern "C" {
#include "i_sound.h"
#include "memio.h"
#include "mus2mid.h"
}

#undef LOG_TAG
#define LOG_TAG "Doom4OH"

namespace {

constexpr int32_t kMaxChunkFrames = 4096;
constexpr int32_t kRenderBlock = 512;
constexpr int kDrumChannel = 9;    // MIDI channel 10 (0-based) — GM percussion.
constexpr unsigned int kDrumBank = 128;

struct Song {
    tml_message *head;
};

std::mutex g_lock;
std::string g_sfPath;
fluid_settings_t *g_settings = nullptr;
fluid_synth_t *g_synth = nullptr;
int g_gainVolume = 127;
Song *g_current = nullptr;
tml_message *g_cursor = nullptr;
bool g_playing = false;
bool g_looping = false;
bool g_paused = false;
double g_msec = 0.0;
std::vector<int16_t> g_tmp;

// FluidLite exposes no "all notes off" call; MIDI CC 123 does it per channel.
void AllNotesOff()
{
    if (g_synth == nullptr) {
        return;
    }
    for (int ch = 0; ch < 16; ch++) {
        fluid_synth_cc(g_synth, ch, 123, 0); // All Notes Off
    }
}

// Full reset for a fresh song: clears notes, controllers and programs, then restores
// the GM percussion bank on channel 10 (system_reset drops every channel to bank 0).
void ResetForNewSong()
{
    if (g_synth == nullptr) {
        return;
    }
    fluid_synth_system_reset(g_synth);
    fluid_synth_bank_select(g_synth, kDrumChannel, kDrumBank);
    fluid_synth_program_change(g_synth, kDrumChannel, 0);
}

void ApplyGain()
{
    if (g_synth != nullptr) {
        // DOOM volume 0..127 -> FluidSynth gain. 0.5 at full keeps music present
        // without clipping once summed with SFX in the mixer.
        fluid_synth_set_gain(g_synth, static_cast<float>(std::clamp(g_gainVolume, 0, 127)) / 127.0f * 0.5f);
    }
}

void ProcessMidiUpTo(double msec)
{
    while (g_cursor != nullptr && g_cursor->time <= msec) {
        switch (g_cursor->type) {
            case TML_PROGRAM_CHANGE:
                fluid_synth_program_change(g_synth, g_cursor->channel, g_cursor->program);
                break;
            case TML_NOTE_ON:
                fluid_synth_noteon(g_synth, g_cursor->channel, g_cursor->key, g_cursor->velocity);
                break;
            case TML_NOTE_OFF:
                fluid_synth_noteoff(g_synth, g_cursor->channel, g_cursor->key);
                break;
            case TML_PITCH_BEND:
                fluid_synth_pitch_bend(g_synth, g_cursor->channel, g_cursor->pitch_bend);
                break;
            case TML_CONTROL_CHANGE:
                fluid_synth_cc(g_synth, g_cursor->channel, g_cursor->control, g_cursor->control_value);
                break;
            default:
                break;
        }
        g_cursor = g_cursor->next;
    }
}

boolean I_OHOS_InitMusic(void)
{
    std::lock_guard<std::mutex> lock(g_lock);
    if (g_synth == nullptr && !g_sfPath.empty()) {
        g_settings = new_fluid_settings();
        fluid_settings_setnum(g_settings, "synth.sample-rate", static_cast<double>(audio::kSampleRate));
        fluid_settings_setint(g_settings, "synth.polyphony", 64);
        g_synth = new_fluid_synth(g_settings);
        if (g_synth != nullptr && fluid_synth_sfload(g_synth, g_sfPath.c_str(), 1) >= 0) {
            fluid_synth_set_reverb_on(g_synth, 1);
            fluid_synth_set_chorus_on(g_synth, 1);
            fluid_synth_bank_select(g_synth, kDrumChannel, kDrumBank); // GM percussion channel
            ApplyGain();
            g_tmp.resize(static_cast<size_t>(kMaxChunkFrames) * 2);
            OH_LOG_INFO(LOG_APP, "music: soundfont loaded via FluidLite (reverb+chorus on)");
        } else {
            OH_LOG_ERROR(LOG_APP, "music: cannot load soundfont %{public}s — music disabled", g_sfPath.c_str());
            if (g_synth != nullptr) {
                delete_fluid_synth(g_synth);
                g_synth = nullptr;
            }
            delete_fluid_settings(g_settings);
            g_settings = nullptr;
        }
    }
    return true; // a missing soundfont does not block the game — it runs without music
}

void I_OHOS_ShutdownMusic(void)
{
    std::lock_guard<std::mutex> lock(g_lock);
    g_playing = false;
    g_cursor = nullptr;
    g_current = nullptr;
    if (g_synth != nullptr) {
        delete_fluid_synth(g_synth);
        g_synth = nullptr;
    }
    if (g_settings != nullptr) {
        delete_fluid_settings(g_settings);
        g_settings = nullptr;
    }
}

void I_OHOS_SetMusicVolume(int volume)
{
    std::lock_guard<std::mutex> lock(g_lock);
    g_gainVolume = volume;
    ApplyGain();
}

void I_OHOS_PauseSong(void)
{
    std::lock_guard<std::mutex> lock(g_lock);
    g_paused = true; // MixInto stops mixing music; notes resume on unpause
}

void I_OHOS_ResumeSong(void)
{
    std::lock_guard<std::mutex> lock(g_lock);
    g_paused = false;
}

void *I_OHOS_RegisterSong(void *data, int len)
{
    if (data == nullptr || len < 4) {
        return nullptr;
    }
    const auto *bytes = static_cast<const uint8_t *>(data);

    std::vector<uint8_t> midi;
    if (std::memcmp(bytes, "MUS\x1a", 4) == 0) {
        MEMFILE *in = mem_fopen_read(data, static_cast<size_t>(len));
        MEMFILE *out = mem_fopen_write();
        const boolean failed = mus2mid(in, out); // true = conversion error
        if (!failed) {
            void *buf = nullptr;
            size_t buflen = 0;
            mem_get_buf(out, &buf, &buflen);
            midi.assign(static_cast<uint8_t *>(buf), static_cast<uint8_t *>(buf) + buflen);
        }
        mem_fclose(in);
        mem_fclose(out);
        if (failed) {
            OH_LOG_ERROR(LOG_APP, "music: mus2mid failed");
            return nullptr;
        }
    } else {
        midi.assign(bytes, bytes + len);
    }

    tml_message *msgs = tml_load_memory(midi.data(), static_cast<int>(midi.size()));
    if (msgs == nullptr) {
        OH_LOG_ERROR(LOG_APP, "music: tml parse failed (%{public}d B)", len);
        return nullptr;
    }
    return new Song{msgs};
}

void I_OHOS_UnRegisterSong(void *handle)
{
    auto *song = static_cast<Song *>(handle);
    if (song == nullptr) {
        return;
    }
    std::lock_guard<std::mutex> lock(g_lock);
    if (g_current == song) {
        g_playing = false;
        g_cursor = nullptr;
        g_current = nullptr;
        AllNotesOff();
    }
    tml_free(song->head);
    delete song;
}

void I_OHOS_PlaySong(void *handle, boolean looping)
{
    auto *song = static_cast<Song *>(handle);
    if (song == nullptr) {
        return;
    }
    std::lock_guard<std::mutex> lock(g_lock);
    if (g_synth == nullptr) {
        return;
    }
    ResetForNewSong();
    g_current = song;
    g_cursor = song->head;
    g_msec = 0.0;
    g_looping = looping != 0;
    g_paused = false;
    g_playing = true;
    OH_LOG_INFO(LOG_APP, "music: song started (looping=%{public}d)", looping);
}

void I_OHOS_StopSong(void)
{
    std::lock_guard<std::mutex> lock(g_lock);
    g_playing = false;
    g_cursor = nullptr;
    g_current = nullptr;
    AllNotesOff();
}

boolean I_OHOS_MusicIsPlaying(void)
{
    std::lock_guard<std::mutex> lock(g_lock);
    return g_playing;
}

snddevice_t g_musicDevices[] = {SNDDEVICE_SB, SNDDEVICE_GENMIDI};

} // namespace

namespace music {

void SetSoundFontPath(const std::string &path)
{
    std::lock_guard<std::mutex> lock(g_lock);
    g_sfPath = path;
}

void MixInto(int32_t *accum, int32_t frameCount)
{
    std::unique_lock<std::mutex> lock(g_lock, std::try_to_lock);
    if (!lock.owns_lock()) {
        return; // song change in progress — one tick without music instead of blocking
    }
    if (g_synth == nullptr || !g_playing || g_paused) {
        return;
    }

    int32_t done = 0;
    while (done < frameCount) {
        const int32_t block = std::min(frameCount - done, kRenderBlock);
        g_msec += block * (1000.0 / audio::kSampleRate);
        ProcessMidiUpTo(g_msec);
        if (g_cursor == nullptr) {
            if (g_looping && g_current != nullptr) {
                g_cursor = g_current->head;
                g_msec = 0.0;
                AllNotesOff();
            } else if (!g_looping) {
                g_playing = false; // tail rings out in this block, then silence
            }
        }
        fluid_synth_write_s16(g_synth, block, g_tmp.data(), 0, 2, g_tmp.data(), 1, 2);
        for (int32_t i = 0; i < block * 2; i++) {
            accum[static_cast<size_t>(done) * 2 + i] += g_tmp[i];
        }
        done += block;
    }
}

} // namespace music

extern "C" music_module_t DG_music_module = {
    g_musicDevices,
    2,
    I_OHOS_InitMusic,
    I_OHOS_ShutdownMusic,
    I_OHOS_SetMusicVolume,
    I_OHOS_PauseSong,
    I_OHOS_ResumeSong,
    I_OHOS_RegisterSong,
    I_OHOS_UnRegisterSong,
    I_OHOS_PlaySong,
    I_OHOS_StopSong,
    I_OHOS_MusicIsPlaying,
    nullptr, // Poll — i_sound.c checks for NULL before calling
};
