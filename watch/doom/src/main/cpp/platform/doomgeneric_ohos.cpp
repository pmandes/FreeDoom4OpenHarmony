#include "doomgeneric_ohos.h"

#include <atomic>
#include <chrono>
#include <cstdio>
#include <cstring>
#include <ctime>
#include <string>
#include <thread>
#include <vector>

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
}

// When the engine enters slot-name editing (saveStringEnter 0->1), we write an
// automatic name "MAP HH:MM DD/MM" straight into the buffer and inject Enter,
// which confirms the save (overwriting the slot if it was occupied). No keyboard —
// on a watch there is no way to type text anyway.
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

    // By default next/prev weapon are unbound (0); we bind them after Create,
    // so the loaded config does not overwrite them. Codes consistent with MapAction.
    key_prevweapon = '[';
    key_nextweapon = ']';
    // "press Y" prompts (quit, etc.) are confirmed with the on-screen ENTER —
    // the overlay has no Y key; ESC still cancels the prompt.
    key_menu_confirm = KEY_ENTER;

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
            next = now; // don't catch up on backlog — avoids a death spiral
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
