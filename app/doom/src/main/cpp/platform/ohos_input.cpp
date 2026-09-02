#include "ohos_input.h"

#include <atomic>
#include <cstdint>

#include "doomkeys.h"

namespace input {
namespace {

constexpr int kCapacity = 64; // power of two

struct KeyEvent {
    unsigned char key;
    bool pressed;
};

// SPSC ring buffer: producer = UI thread, consumer = game thread.
KeyEvent g_queue[kCapacity];
std::atomic<uint32_t> g_head{0}; // write (producer)
std::atomic<uint32_t> g_tail{0}; // read (consumer)

unsigned char MapAction(int action)
{
    switch (action) {
        case kUp:
            return KEY_UPARROW;
        case kDown:
            return KEY_DOWNARROW;
        case kLeft:
            return KEY_LEFTARROW;
        case kRight:
            return KEY_RIGHTARROW;
        case kFire:
            return KEY_FIRE;
        case kUse:
            return KEY_USE;
        case kEnter:
            return KEY_ENTER;
        case kEscape:
            return KEY_ESCAPE;
        case kStrafeLeft:
            return KEY_STRAFE_L;
        case kStrafeRight:
            return KEY_STRAFE_R;
        case kPrevWeapon:
            return '['; // bound in doomgeneric_ohos.cpp after Create
        case kNextWeapon:
            return ']';
        case kRun:
            return KEY_RSHIFT;
        default:
            return 0;
    }
}

} // namespace

void PushRawKey(int key, bool pressed)
{
    if (key <= 0 || key > 255) {
        return;
    }
    const uint32_t head = g_head.load(std::memory_order_relaxed);
    const uint32_t tail = g_tail.load(std::memory_order_acquire);
    if (head - tail >= kCapacity) {
        return; // queue full — the event is dropped, better than blocking the UI
    }
    g_queue[head % kCapacity] = {static_cast<unsigned char>(key), pressed};
    g_head.store(head + 1, std::memory_order_release);
}

void PushAction(int action, bool pressed)
{
    const unsigned char key = MapAction(action);
    if (key != 0) {
        PushRawKey(key, pressed);
    }
}

bool PopKey(int *pressed, unsigned char *key)
{
    const uint32_t tail = g_tail.load(std::memory_order_relaxed);
    const uint32_t head = g_head.load(std::memory_order_acquire);
    if (tail == head) {
        return false;
    }
    const KeyEvent &ev = g_queue[tail % kCapacity];
    *pressed = ev.pressed ? 1 : 0;
    *key = ev.key;
    g_tail.store(tail + 1, std::memory_order_release);
    return true;
}

} // namespace input
