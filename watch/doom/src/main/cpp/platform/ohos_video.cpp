#include "ohos_video.h"

#include <cerrno>
#include <cstring>
#include <mutex>
#include <vector>

#include <sys/mman.h>

#include <native_window/external_window.h>
#include <native_buffer/native_buffer.h>

#include "hilog/log.h"

#undef LOG_TAG
#define LOG_TAG "Doom4OH"

namespace video {
namespace {

std::mutex g_windowMutex;
NativeWindow *g_window = nullptr;

// Target buffer size (= surface size in px). We scale the 320x200 frame ourselves
// nearest-neighbor, so the compositor does not interpolate.
int g_dstW = kFbWidth;
int g_dstH = kFbHeight;

// For each destination column: the source column index (nearest). Recomputed
// only when the buffer width changes — takes the division out of the per-pixel loop.
std::vector<int> g_srcX;
int g_srcXForWidth = 0;

void BuildSrcXTable(int dstW)
{
    if (dstW == g_srcXForWidth) {
        return;
    }
    g_srcX.resize(static_cast<size_t>(dstW));
    for (int dx = 0; dx < dstW; dx++) {
        int sx = static_cast<int>((static_cast<int64_t>(dx) * kFbWidth) / dstW);
        if (sx >= kFbWidth) {
            sx = kFbWidth - 1;
        }
        g_srcX[static_cast<size_t>(dx)] = sx;
    }
    g_srcXForWidth = dstW;
}

} // namespace

void OnSurfaceAvailable(NativeWindow *window, int width, int height)
{
    std::lock_guard<std::mutex> lock(g_windowMutex);
    g_window = window;
    // The buffer gets the full surface size; we scale the frame nearest-neighbor in the blit,
    // so the image is pixel-perfect (the compositor blits 1:1, no bilinear blur).
    // Fall back to 320x200 (compositor scales) when the size is not yet known.
    g_dstW = width >= kFbWidth ? width : kFbWidth;
    g_dstH = height >= kFbHeight ? height : kFbHeight;
    OH_NativeWindow_NativeWindowHandleOpt(window, SET_BUFFER_GEOMETRY, g_dstW, g_dstH);
    // The emulator compositor renders BGRA_8888 as a black screen,
    // so we stay on RGBA_8888 + R<->B swap in the blit.
    OH_NativeWindow_NativeWindowHandleOpt(window, SET_FORMAT, NATIVEBUFFER_PIXEL_FMT_RGBA_8888);
    // Without CPU_WRITE in usage the buffer also composits as black.
    OH_NativeWindow_NativeWindowHandleOpt(
        window, SET_USAGE, NATIVEBUFFER_USAGE_CPU_READ | NATIVEBUFFER_USAGE_CPU_WRITE | NATIVEBUFFER_USAGE_MEM_DMA);
    OH_LOG_INFO(LOG_APP, "video: surface available %{public}dx%{public}d", g_dstW, g_dstH);
}

void OnSurfaceLost()
{
    std::lock_guard<std::mutex> lock(g_windowMutex);
    g_window = nullptr;
    OH_LOG_INFO(LOG_APP, "video: surface lost");
}

bool PresentFrame(const uint32_t *frame)
{
    std::lock_guard<std::mutex> lock(g_windowMutex);
    if (g_window == nullptr || frame == nullptr) {
        return false;
    }

    OHNativeWindowBuffer *buffer = nullptr;
    int fenceFd = -1;
    int32_t ret = OH_NativeWindow_NativeWindowRequestBuffer(g_window, &buffer, &fenceFd);
    if (ret != 0 || buffer == nullptr) {
        OH_LOG_ERROR(LOG_APP, "video: RequestBuffer failed: %{public}d", ret);
        return false;
    }

    BufferHandle *handle = OH_NativeWindow_GetBufferHandleFromNative(buffer);
    bool ok = false;
    if (handle != nullptr) {
        // CPU-writable mapping. Prefer OH_NativeBuffer_Map (the portable graphics-buffer
        // mapping API): a raw mmap on the buffer fd is denied with EACCES on pure
        // OpenHarmony compositors (it works on HarmonyOS). Fall back to mmap only if the
        // NativeBuffer path is unavailable.
        OH_NativeBuffer *nb = nullptr;
        bool nbMapped = false;
        void *mmapped = nullptr;
        uint8_t *dst = nullptr;
        if (OH_NativeBuffer_FromNativeWindowBuffer(buffer, &nb) == 0 && nb != nullptr) {
            void *virAddr = nullptr;
            if (OH_NativeBuffer_Map(nb, &virAddr) == 0 && virAddr != nullptr) {
                dst = static_cast<uint8_t *>(virAddr);
                nbMapped = true;
            }
        }
        if (dst == nullptr && handle->fd >= 0) {
            mmapped = mmap(nullptr, handle->size, PROT_READ | PROT_WRITE, MAP_SHARED, handle->fd, 0);
            if (mmapped != MAP_FAILED) {
                dst = static_cast<uint8_t *>(mmapped);
            } else {
                mmapped = nullptr;
            }
        }
        if (dst != nullptr) {
            // Scale 320x200 -> buffer size nearest-neighbor (pixel-perfect: no
            // interpolation, sharp pixels). handle->width/height is the real buffer
            // size, stride in bytes (can be > width*4). Conversion 0xAARRGGBB (doomgeneric)
            // -> RGBA_8888: swap R<->B and force full alpha (doomgeneric leaves
            // 0x00 in the top byte, which would be transparent).
            const int dstW = handle->width;
            const int dstH = handle->height;
            BuildSrcXTable(dstW);
            const int *srcX = g_srcX.data();
            for (int dy = 0; dy < dstH; dy++) {
                int sy = static_cast<int>((static_cast<int64_t>(dy) * kFbHeight) / dstH);
                if (sy >= kFbHeight) {
                    sy = kFbHeight - 1;
                }
                const uint32_t *srcRow = frame + static_cast<size_t>(sy) * kFbWidth;
                auto *dstRow = reinterpret_cast<uint32_t *>(dst + static_cast<size_t>(dy) * handle->stride);
                for (int dx = 0; dx < dstW; dx++) {
                    const uint32_t v = srcRow[srcX[dx]];
                    dstRow[dx] = 0xFF000000u | (v & 0x0000FF00u) | ((v >> 16) & 0xFFu) | ((v & 0xFFu) << 16);
                }
            }
            if (nbMapped) {
                OH_NativeBuffer_Unmap(nb);
            } else if (mmapped != nullptr) {
                munmap(mmapped, handle->size);
            }
            ok = true;
        } else {
            OH_LOG_ERROR(LOG_APP, "video: buffer map failed (errno=%{public}d fd=%{public}d size=%{public}u)",
                         errno, handle->fd, static_cast<uint32_t>(handle->size));
        }
    }

    // Buffer contract: every requested buffer is returned via Flush or Abort.
    if (ok) {
        Region region{nullptr, 0};
        ret = OH_NativeWindow_NativeWindowFlushBuffer(g_window, buffer, fenceFd, region);
        if (ret != 0) {
            OH_LOG_ERROR(LOG_APP, "video: FlushBuffer failed: %{public}d", ret);
            ok = false;
        }
    } else {
        OH_NativeWindow_NativeWindowAbortBuffer(g_window, buffer);
    }
    return ok;
}

} // namespace video
