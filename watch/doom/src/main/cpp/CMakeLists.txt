cmake_minimum_required(VERSION 3.5.0)
project(doom4oh C CXX)

set(CMAKE_C_STANDARD 99)
set(CMAKE_CXX_STANDARD 17)

# Shared by the engine and the platform layer — DOOMGENERIC_RESX/RESY must be
# identical everywhere doomgeneric.h is pulled in.
add_compile_definitions(
    NORMALUNIX
    LINUX
    SNDSERV
    _DEFAULT_SOURCE
    DOOMGENERIC_RESX=320
    DOOMGENERIC_RESY=200
    FEATURE_SOUND
)

set(DOOMGENERIC_DIR ${CMAKE_CURRENT_SOURCE_DIR}/engine/doomgeneric)

# List from the doomgeneric Makefile (SRC_DOOM) without the platform backend doomgeneric_xlib.c.
set(DOOMCORE_SOURCES
    dummy.c am_map.c doomdef.c doomstat.c dstrings.c d_event.c d_items.c d_iwad.c
    d_loop.c d_main.c d_mode.c d_net.c f_finale.c f_wipe.c g_game.c hu_lib.c
    hu_stuff.c info.c i_cdmus.c i_endoom.c i_joystick.c i_scale.c i_sound.c
    i_system.c i_timer.c memio.c m_argv.c m_bbox.c m_cheat.c m_config.c
    m_controls.c m_fixed.c m_menu.c m_misc.c m_random.c p_ceilng.c p_doors.c
    p_enemy.c p_floor.c p_inter.c p_lights.c p_map.c p_maputl.c p_mobj.c
    p_plats.c p_pspr.c p_saveg.c p_setup.c p_sight.c p_spec.c p_switch.c
    p_telept.c p_tick.c p_user.c r_bsp.c r_data.c r_draw.c r_main.c r_plane.c
    r_segs.c r_sky.c r_things.c sha1.c sounds.c statdump.c st_lib.c st_stuff.c
    s_sound.c tables.c v_video.c wi_stuff.c w_checksum.c w_file.c w_main.c
    w_wad.c z_zone.c w_file_stdc.c i_input.c i_video.c doomgeneric.c
    mus2mid.c
)
list(TRANSFORM DOOMCORE_SOURCES PREPEND ${DOOMGENERIC_DIR}/)

add_library(doomcore STATIC ${DOOMCORE_SOURCES})
target_include_directories(doomcore PUBLIC ${DOOMGENERIC_DIR})
# shim/SDL_mixer.h: i_sound.c includes <SDL_mixer.h> under FEATURE_SOUND,
# but doesn't use any Mix_* symbols — an empty header instead of patching the engine.
target_include_directories(doomcore PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/shim)

# TSF synthesis and the mixer must meet the audio callback deadline even
# in debug builds — the rest stays at -O0 for debuggability.
set_source_files_properties(
    platform/ohos_music.cpp
    platform/ohos_sound.cpp
    PROPERTIES COMPILE_OPTIONS "-O2"
)

add_library(doom SHARED
    napi_entry.cpp
    platform/doomgeneric_ohos.cpp
    platform/ohos_audio.cpp
    platform/ohos_files.cpp
    platform/ohos_input.cpp
    platform/ohos_music.cpp
    platform/ohos_sound.cpp
    platform/ohos_video.cpp
)

target_include_directories(doom PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_CURRENT_SOURCE_DIR}/third_party/tsf
)

# Redirect every exit() in libdoom (engine I_Quit/I_Error) to __wrap_exit, which
# shuts the app down gracefully. A raw exit() is aborted by appspawn on
# HarmonyOS/OpenHarmony (SIGABRT crash), see platform/doomgeneric_ohos.cpp.
target_link_options(doom PRIVATE "-Wl,--wrap=exit")

target_link_libraries(doom PUBLIC
    doomcore
    libace_napi.z.so
    libhilog_ndk.z.so
    libace_ndk.z.so
    libnative_window.so
    libnative_buffer.so
    librawfile.z.so
    libohaudio.so
)
