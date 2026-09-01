#include <cstring>
#include <string>

#include <sys/stat.h>

#include <ace/xcomponent/native_interface_xcomponent.h>
#include <rawfile/raw_file_manager.h>

#include "napi/native_api.h"
#include "hilog/log.h"

#include "platform/doomgeneric_ohos.h"
#include "platform/ohos_files.h"
#include "platform/ohos_music.h"
#include "platform/ohos_input.h"
#include "platform/ohos_video.h"

#undef LOG_TAG
#define LOG_TAG "Doom4OH"

static const char *kVersion = "0.13.0-hwkbd";

static napi_value GetVersion(napi_env env, napi_callback_info info)
{
    napi_value result = nullptr;
    napi_create_string_utf8(env, kVersion, strlen(kVersion), &result);
    return result;
}

static std::string GetStringArg(napi_env env, napi_value value)
{
    size_t len = 0;
    napi_get_value_string_utf8(env, value, nullptr, 0, &len);
    std::string out(len, '\0');
    napi_get_value_string_utf8(env, value, out.data(), len + 1, &len);
    return out;
}

// startGame(resourceManager, filesDir, iwadPath?) -> bool
// iwadPath: absolute path to the imported IWAD; empty/missing
// -> falls back to the bundled freedoom1.wad copied from rawfile.
static napi_value StartGame(napi_env env, napi_callback_info info)
{
    size_t argc = 3;
    napi_value args[3] = {nullptr, nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    napi_value result = nullptr;
    if (argc < 2) {
        OH_LOG_ERROR(LOG_APP, "startGame: expected (resourceManager, filesDir, iwadPath?)");
        napi_get_boolean(env, false, &result);
        return result;
    }

    NativeResourceManager *resMgr = OH_ResourceManager_InitNativeResourceManager(env, args[0]);
    const std::string filesDir = GetStringArg(env, args[1]);

    std::string wadPath;
    if (argc >= 3 && args[2] != nullptr) {
        const std::string requested = GetStringArg(env, args[2]);
        struct stat st{};
        if (!requested.empty()) {
            if (stat(requested.c_str(), &st) == 0 && st.st_size > 0) {
                wadPath = requested;
                OH_LOG_INFO(LOG_APP, "startGame: selected IWAD %{public}s", wadPath.c_str());
            } else {
                OH_LOG_ERROR(LOG_APP, "startGame: IWAD %{public}s unavailable — falling back to Freedoom",
                             requested.c_str());
            }
        }
    }

    bool ok = resMgr != nullptr;
    if (ok && wadPath.empty()) {
        wadPath = filesDir + "/freedoom1.wad";
        ok = files::EnsureRawFileCopied(resMgr, "freedoom1.wad", wadPath);
    }
    if (ok) {
        // The soundfont is optional — without it the game runs with SFX but no music.
        const std::string sfPath = filesDir + "/TimGM6mb.sf2";
        if (files::EnsureRawFileCopied(resMgr, "TimGM6mb.sf2", sfPath)) {
            music::SetSoundFontPath(sfPath);
        }
    }
    if (resMgr != nullptr) {
        OH_ResourceManager_ReleaseNativeResourceManager(resMgr);
    }
    if (ok) {
        ok = game::Start(wadPath, filesDir);
    }
    napi_get_boolean(env, ok, &result);
    return result;
}

// pushChar(code) — raw ASCII character (down+up) for typing text in the engine
// (save names). Backspace = 0x7f, Enter = 13.
static napi_value PushChar(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (argc >= 1) {
        int32_t code = 0;
        napi_get_value_int32(env, args[0], &code);
        input::PushRawKey(code, true);
        input::PushRawKey(code, false);
    }
    return nullptr;
}

// pushRawKey(code, pressed) — raw doomkeys/ASCII code from a physical keyboard
// (down/up separately, since keys can be held).
static napi_value PushRawKeyNapi(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value args[2] = {nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (argc >= 2) {
        int32_t code = 0;
        bool pressed = false;
        napi_get_value_int32(env, args[0], &code);
        napi_get_value_bool(env, args[1], &pressed);
        input::PushRawKey(code, pressed);
    }
    return nullptr;
}

static napi_value PauseGame(napi_env env, napi_callback_info info)
{
    game::Pause();
    return nullptr;
}

static napi_value ResumeGame(napi_env env, napi_callback_info info)
{
    game::Resume();
    return nullptr;
}

// pushKey(action, pressed) — actions from the input::Action enum; called from the ArkTS overlay.
static napi_value PushKey(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value args[2] = {nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (argc >= 2) {
        int32_t action = -1;
        bool pressed = false;
        napi_get_value_int32(env, args[0], &action);
        napi_get_value_bool(env, args[1], &pressed);
        input::PushAction(action, pressed);
    }
    return nullptr;
}

static void OnSurfaceCreated(OH_NativeXComponent *component, void *window)
{
    uint64_t width = 0;
    uint64_t height = 0;
    OH_NativeXComponent_GetXComponentSize(component, window, &width, &height);
    OH_LOG_INFO(LOG_APP, "XComponent: surface created %{public}llu x %{public}llu",
                static_cast<unsigned long long>(width), static_cast<unsigned long long>(height));
    video::OnSurfaceAvailable(static_cast<NativeWindow *>(window), static_cast<int>(width), static_cast<int>(height));
}

static void OnSurfaceChanged(OH_NativeXComponent *component, void *window)
{
    uint64_t width = 0;
    uint64_t height = 0;
    OH_NativeXComponent_GetXComponentSize(component, window, &width, &height);
    OH_LOG_INFO(LOG_APP, "XComponent: surface changed %{public}llu x %{public}llu",
                static_cast<unsigned long long>(width), static_cast<unsigned long long>(height));
    // A surface resize (rotation, layout change) resets the buffer geometry —
    // geometry/format/usage must be set again with the new size, otherwise
    // the game renders in the corner of a full-size buffer.
    video::OnSurfaceAvailable(static_cast<NativeWindow *>(window), static_cast<int>(width), static_cast<int>(height));
}

static void OnSurfaceDestroyed(OH_NativeXComponent *component, void *window)
{
    OH_LOG_INFO(LOG_APP, "XComponent: surface destroyed");
    video::OnSurfaceLost();
}

static void OnDispatchTouchEvent(OH_NativeXComponent *component, void *window)
{
    // Touch is handled in the ArkTS overlay; the native surface ignores dispatched touch events.
}

static OH_NativeXComponent_Callback g_xcomponentCallbacks = {
    .OnSurfaceCreated = OnSurfaceCreated,
    .OnSurfaceChanged = OnSurfaceChanged,
    .OnSurfaceDestroyed = OnSurfaceDestroyed,
    .DispatchTouchEvent = OnDispatchTouchEvent,
};

static void RegisterXComponent(napi_env env, napi_value exports)
{
    napi_value exportInstance = nullptr;
    if (napi_get_named_property(env, exports, OH_NATIVE_XCOMPONENT_OBJ, &exportInstance) != napi_ok) {
        OH_LOG_ERROR(LOG_APP, "XComponent: missing %{public}s export", OH_NATIVE_XCOMPONENT_OBJ);
        return;
    }
    OH_NativeXComponent *component = nullptr;
    if (napi_unwrap(env, exportInstance, reinterpret_cast<void **>(&component)) != napi_ok || component == nullptr) {
        OH_LOG_ERROR(LOG_APP, "XComponent: unwrap failed");
        return;
    }
    OH_NativeXComponent_RegisterCallback(component, &g_xcomponentCallbacks);
    OH_LOG_INFO(LOG_APP, "XComponent: callbacks registered");
}

static napi_value Init(napi_env env, napi_value exports)
{
    napi_property_descriptor desc[] = {
        {"getVersion", nullptr, GetVersion, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"startGame", nullptr, StartGame, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"pushKey", nullptr, PushKey, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"pushChar", nullptr, PushChar, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"pushRawKey", nullptr, PushRawKeyNapi, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"pauseGame", nullptr, PauseGame, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"resumeGame", nullptr, ResumeGame, nullptr, nullptr, nullptr, napi_default, nullptr},
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    RegisterXComponent(env, exports);
    return exports;
}

static napi_module g_module = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "doom",
    .nm_priv = nullptr,
    .reserved = {nullptr},
};

extern "C" __attribute__((constructor)) void RegisterDoomModule(void)
{
    napi_module_register(&g_module);
}
