#ifndef DOOM4OH_OHOS_FILES_H
#define DOOM4OH_OHOS_FILES_H

#include <string>

struct NativeResourceManager;

namespace files {

// Copies the rawfile named rawName to destPath if the file does not yet exist
// or has a different size than the source. Returns true when the file is in place on exit.
bool EnsureRawFileCopied(NativeResourceManager *resMgr, const char *rawName, const std::string &destPath);

} // namespace files

#endif // DOOM4OH_OHOS_FILES_H
