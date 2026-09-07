#include "doomgeneric_ohos.h"

#include <atomic>
#include <cctype>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <ctime>
#include <string>
#include <thread>
#include <vector>

#include <sys/stat.h>
#include <unistd.h>

#include "hilog/log.h"

#include "doomgeneric.h"
#include "doomkeys.h"
#include "ohos_audio.h"
#include "ohos_input.h"
#include "ohos_video.h"

#undef LOG_TAG
#define LOG_TAG "Doom4OH"

// Bindings from the engine's m_controls.c (C linkage).
extern "C" {
extern int key_prevweapon;
extern int key_nextweapon;
extern int key_menu_confirm;
// Save-menu state (m_menu.c) and in-game position (doomstat) — for the auto save name.
extern int saveStringEnter;
extern int saveSlot;
extern char savegamestrings[10][24]; // SAVESTRINGSIZE = 24
extern int gamemode;                 // GameMode_t: 1 == commercial (Doom II)
extern int gameepisode;
extern int gamemap;
extern char *savegamedir;            // d_main.c: directory savegames are read/written from
}

// When the engine enters slot-name editing (saveStringEnter 0->1), we write an
// automatic name "MAP HH:MM DD/MM" straight into the buffer and inject Enter,
// which confirms the save (overwriting the slot if it was in use). No keyboard needed.
static void AutoFillSaveName()
{
    static int prevSaveStringEnter = 0;
    if (saveStringEnter && !prevSaveStringEnter) {
        const time_t now = time(nullptr);
        struct tm lt{};
        localtime_r(&now, &lt);
        if (gamemode == 1 /* commercial */) {
            snprintf(savegamestrings[saveSlot], 24, "MAP%02d %02d:%02d %02d/%02d", gamemap, lt.tm_hour,
                     lt.tm_min, lt.tm_mday, lt.tm_mon + 1);
        } else {
            snprintf(savegamestrings[saveSlot], 24, "E%dM%d %02d:%02d %02d/%02d", gameepisode, gamemap, lt.tm_hour,
                     lt.tm_min, lt.tm_mday, lt.tm_mon + 1);
        }
        input::PushRawKey(KEY_ENTER, true);
        input::PushRawKey(KEY_ENTER, false);
    }
    prevSaveStringEnter = saveStringEnter;
}

// HarmonyOS/OpenHarmony forbid an app process from calling exit(): appspawn
// intercepts it and aborts (SIGABRT), which surfaces as a crash. The Doom engine
// calls exit() when quitting (I_Quit) and on fatal errors (I_Error). We redirect
// every exit() in libdoom to this wrapper via the linker (-Wl,--wrap=exit) and turn
// it into a graceful shutdown: raise a flag the ArkTS side polls (it calls
// terminateSelf) and park this thread so no engine code runs past the exit point.
static std::atomic<bool> g_quitRequested{false};

extern "C" void __wrap_exit(int /*code*/)
{
    g_quitRequested.store(true, std::memory_order_release);
    OH_LOG_INFO(LOG_APP, "exit() intercepted -> requesting graceful terminateSelf");
    for (;;) {
        std::this_thread::sleep_for(std::chrono::milliseconds(200));
    }
}

namespace game {
namespace {

std::thread g_gameThread;
std::atomic<bool> g_running{false};
std::atomic<bool> g_paused{false};

std::string g_wadPath;
std::string g_workDir;

// Engine stdout/stderr (printf in I_Error, startup messages) -> hilog,
// otherwise Doom's diagnostics vanish without a trace.
void StartStdioRelay()
{
    static bool started = false;
    if (started) {
        return;
    }
    started = true;

    int fds[2];
    if (pipe(fds) != 0) {
        return;
    }
    setvbuf(stdout, nullptr, _IOLBF, 0);
    setvbuf(stderr, nullptr, _IONBF, 0);
    dup2(fds[1], STDOUT_FILENO);
    dup2(fds[1], STDERR_FILENO);
    close(fds[1]);

    std::thread([fd = fds[0]]() {
        char buf[512];
        std::string line;
        ssize_t n;
        while ((n = read(fd, buf, sizeof(buf))) > 0) {
            for (ssize_t i = 0; i < n; i++) {
                if (buf[i] == '\n') {
                    OH_LOG_INFO(LOG_APP, "doom: %{public}s", line.c_str());
                    line.clear();
                } else {
                    line.push_back(buf[i]);
                }
            }
        }
    }).detach();
}

// Filesystem-safe base name of a WAD path (no directory, no extension).
static std::string WadBaseName(const std::string &path)
{
    const size_t slash = path.find_last_of('/');
    std::string base = (slash == std::string::npos) ? path : path.substr(slash + 1);
    const size_t dot = base.find_last_of('.');
    if (dot != std::string::npos) {
        base = base.substr(0, dot);
    }
    for (char &c : base) {
        if (!std::isalnum(static_cast<unsigned char>(c)) && c != '_' && c != '-') {
            c = '_';
        }
    }
    return base.empty() ? std::string("iwad") : base;
}

// Cheap content fingerprint (FNV-1a over the file size + first 4 KB, which covers the
// WAD header and first lumps). Distinguishes different IWADs even when renamed to the
// same base name, so their savegame directories never collide.
static std::string IwadFingerprint(const std::string &path)
{
    uint32_t h = 2166136261u; // FNV-1a offset basis
    auto mix = [&h](const unsigned char *p, size_t n) {
        for (size_t i = 0; i < n; i++) {
            h ^= p[i];
            h *= 16777619u;
        }
    };
    struct stat st{};
    if (stat(path.c_str(), &st) == 0) {
        const uint64_t sz = static_cast<uint64_t>(st.st_size);
        mix(reinterpret_cast<const unsigned char *>(&sz), sizeof(sz));
    }
    FILE *f = fopen(path.c_str(), "rb");
    if (f != nullptr) {
        unsigned char buf[4096];
        const size_t n = fread(buf, 1, sizeof(buf), f);
        mix(buf, n);
        fclose(f);
    }
    char hex[9];
    snprintf(hex, sizeof(hex), "%08x", h);
    return std::string(hex);
}

// Removes the pre-fix shared save location (workDir/.savegame and any stray
// workDir/doomsavN.dsg). Those slots mixed IWADs and could only ever crash on load
// now that saves are per-IWAD; they can't be migrated (a shared save records no IWAD),
// so drop them once. Idempotent.
static void RemoveLegacySaves()
{
    const std::string legacy = g_workDir + "/.savegame";
    for (int i = 0; i < 8; i++) {
        char name[32];
        snprintf(name, sizeof(name), "/doomsav%d.dsg", i);
        unlink((legacy + name).c_str());
        unlink((g_workDir + name).c_str());
    }
    unlink((legacy + "/temp.dsg").c_str());
    rmdir(legacy.c_str()); // only succeeds once the directory is empty
}

// Points savegamedir at a per-IWAD subdirectory. Vanilla DOOM savegames don't record
// which IWAD they belong to, and the engine only namespaces saves by gamemission, so
// two IWADs of the same mission (e.g. Freedoom Phase 1 vs Ultimate Doom) would share a
// slot. Loading a save across mismatched maps corrupts P_UnArchiveSpecials and crashes,
// so give every distinct IWAD file its own save directory (this also removes the
// confusing shared save slots).
static void SetPerIwadSaveDir()
{
    const std::string id = WadBaseName(g_wadPath) + "_" + IwadFingerprint(g_wadPath);
    const std::string root = g_workDir + "/saves";
    const std::string dir = root + "/" + id + "/"; // trailing slash: engine prepends it to the file name
    mkdir(root.c_str(), 0770);
    mkdir(dir.c_str(), 0770);
    savegamedir = strdup(dir.c_str());
    RemoveLegacySaves();
    OH_LOG_INFO(LOG_APP, "game: savegamedir=%{public}s", savegamedir);
}

void GameLoop()
{
    if (chdir(g_workDir.c_str()) != 0) {
        OH_LOG_ERROR(LOG_APP, "game: chdir(%{public}s) failed", g_workDir.c_str());
    }

    std::vector<std::string> args = {"doomgeneric", "-iwad", g_wadPath};
    std::vector<char *> argv;
    argv.reserve(args.size());
    for (auto &a : args) {
        argv.push_back(a.data());
    }

    OH_LOG_INFO(LOG_APP, "game: doomgeneric_Create, iwad=%{public}s", g_wadPath.c_str());
    doomgeneric_Create(static_cast<int>(argv.size()), argv.data());

    // By default next/prev weapon are unbound (0); we bind them after Create
    // so the loaded config can't override them. Codes match MapAction.
    key_prevweapon = '[';
    key_nextweapon = ']';
    // "press Y" prompts (quit, etc.) are confirmed with the on-screen ENTER —
    // the overlay has no Y key; ESC still cancels the prompt.
    key_menu_confirm = KEY_ENTER;

    // Isolate savegames per IWAD file (prevents the cross-IWAD load crash).
    SetPerIwadSaveDir();

    OH_LOG_INFO(LOG_APP, "game: engine initialized, entering tick loop");

    // Pacing: tick + render every ~1/35 s (Doom's native tick rate).
    constexpr auto kFramePeriod = std::chrono::microseconds(1000000 / 35);
    auto next = std::chrono::steady_clock::now();
    while (g_running.load(std::memory_order_acquire)) {
        if (g_paused.load(std::memory_order_acquire)) {
            std::this_thread::sleep_for(std::chrono::milliseconds(50));
            next = std::chrono::steady_clock::now();
            continue;
        }
        doomgeneric_Tick();
        AutoFillSaveName();
        next += kFramePeriod;
        const auto now = std::chrono::steady_clock::now();
        if (next > now) {
            std::this_thread::sleep_until(next);
        } else {
            next = now; // don't catch up on backlog — avoids a spiral
        }
    }
    OH_LOG_INFO(LOG_APP, "game: tick loop stopped");
}

} // namespace

bool Start(const std::string &wadPath, const std::string &workDir)
{
    if (g_running.exchange(true)) {
        return false;
    }
    StartStdioRelay();
    g_wadPath = wadPath;
    g_workDir = workDir;
    g_gameThread = std::thread(GameLoop);
    return true;
}

void Stop()
{
    if (g_running.exchange(false)) {
        if (g_gameThread.joinable()) {
            g_gameThread.join();
        }
    }
}

bool IsRunning() { return g_running.load(std::memory_order_acquire); }

bool IsQuitRequested() { return g_quitRequested.load(std::memory_order_acquire); }

void Pause()
{
    g_paused.store(true, std::memory_order_release);
    audio::Pause();
    OH_LOG_INFO(LOG_APP, "game: paused");
}

void Resume()
{
    g_paused.store(false, std::memory_order_release);
    audio::Resume();
    OH_LOG_INFO(LOG_APP, "game: resumed");
}

} // namespace game

// ── doomgeneric platform API implementation ─────────────────────────────────

extern "C" {

void DG_Init() {}

void DG_DrawFrame()
{
    video::PresentFrame(DG_ScreenBuffer);
}

void DG_SleepMs(uint32_t ms)
{
    usleep(ms * 1000u);
}

uint32_t DG_GetTicksMs()
{
    const auto now = std::chrono::steady_clock::now().time_since_epoch();
    return static_cast<uint32_t>(std::chrono::duration_cast<std::chrono::milliseconds>(now).count());
}

int DG_GetKey(int *pressed, unsigned char *key)
{
    return input::PopKey(pressed, key) ? 1 : 0;
}

void DG_SetWindowTitle(const char *title) {}

} // extern "C"
