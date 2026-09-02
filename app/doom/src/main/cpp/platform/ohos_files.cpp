#include "ohos_files.h"

#include <cstdio>
#include <memory>
#include <vector>

#include <sys/stat.h>

#include <rawfile/raw_file.h>
#include <rawfile/raw_file_manager.h>

#include "hilog/log.h"

#undef LOG_TAG
#define LOG_TAG "Doom4OH"

namespace files {

bool EnsureRawFileCopied(NativeResourceManager *resMgr, const char *rawName, const std::string &destPath)
{
    RawFile *raw = OH_ResourceManager_OpenRawFile(resMgr, rawName);
    if (raw == nullptr) {
        OH_LOG_ERROR(LOG_APP, "files: rawfile '%{public}s' not found", rawName);
        return false;
    }
    const long size = OH_ResourceManager_GetRawFileSize(raw);

    struct stat st{};
    if (stat(destPath.c_str(), &st) == 0 && st.st_size == size) {
        OH_ResourceManager_CloseRawFile(raw);
        OH_LOG_INFO(LOG_APP, "files: %{public}s already present (%{public}ld B)", destPath.c_str(), size);
        return true;
    }

    std::unique_ptr<FILE, decltype(&fclose)> out(fopen(destPath.c_str(), "wb"), fclose);
    if (!out) {
        OH_LOG_ERROR(LOG_APP, "files: cannot open %{public}s for writing", destPath.c_str());
        OH_ResourceManager_CloseRawFile(raw);
        return false;
    }

    std::vector<char> buf(256 * 1024);
    long copied = 0;
    bool ok = true;
    while (copied < size) {
        const long chunk = OH_ResourceManager_ReadRawFile(raw, buf.data(), buf.size());
        if (chunk <= 0) {
            ok = false;
            break;
        }
        if (fwrite(buf.data(), 1, static_cast<size_t>(chunk), out.get()) != static_cast<size_t>(chunk)) {
            ok = false;
            break;
        }
        copied += chunk;
    }
    OH_ResourceManager_CloseRawFile(raw);

    if (!ok || copied != size) {
        OH_LOG_ERROR(LOG_APP, "files: copy failed at %{public}ld/%{public}ld B", copied, size);
        return false;
    }
    OH_LOG_INFO(LOG_APP, "files: copied %{public}s -> %{public}s (%{public}ld B)", rawName, destPath.c_str(), size);
    return true;
}

} // namespace files
