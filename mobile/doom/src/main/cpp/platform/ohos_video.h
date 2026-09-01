#ifndef DOOM4OH_OHOS_VIDEO_H
#define DOOM4OH_OHOS_VIDEO_H

#include <cstdint>

struct NativeWindow;

// Pixels in doomgeneric's convention: uint32_t 0xAARRGGBB (little-endian ⇒ bytes B,G,R,A).
namespace video {

constexpr int kFbWidth = 320;
constexpr int kFbHeight = 200;

// Takes over the surface from the XComponent. width/height is the surface size in pixels
// (from OH_NativeXComponent_GetXComponentSize) — the buffer gets that geometry, and the
// 320x200 frame is scaled nearest-neighbor, so the compositor blits 1:1 (pixel-perfect,
// no bilinear blur). With width/height <= 0 it falls back to 320x200 (compositor scales).
void OnSurfaceAvailable(NativeWindow *window, int width, int height);

// Stops the rendering thread and detaches the NativeWindow. Safe to call repeatedly.
void OnSurfaceLost();

// Copy the 320x200 frame (0xAARRGGBB) into the window buffer and present it.
// Returns false if the surface doesn't exist or presentation failed.
bool PresentFrame(const uint32_t *frame);

} // namespace video

#endif // DOOM4OH_OHOS_VIDEO_H
