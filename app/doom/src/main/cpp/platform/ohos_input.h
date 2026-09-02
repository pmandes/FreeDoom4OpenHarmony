#ifndef DOOM4OH_OHOS_INPUT_H
#define DOOM4OH_OHOS_INPUT_H

namespace input {

// Logical actions from the UI layer (ArkTS passes these values via pushKey).
enum Action {
    kUp = 0,
    kDown = 1,
    kLeft = 2,
    kRight = 3,
    kFire = 4,
    kUse = 5,
    kEnter = 6,
    kEscape = 7,
    kStrafeLeft = 8,
    kStrafeRight = 9,
    kPrevWeapon = 10,
    kNextWeapon = 11,
    kRun = 12,
};

// Producer: UI thread (NAPI). Maps an action to a doomkeys code and enqueues it.
void PushAction(int action, bool pressed);

// Raw key code (ASCII/doomkeys) without mapping — for typing text
// (save names): the character goes into the engine event's data1/data2.
void PushRawKey(int key, bool pressed);

// Consumer: game thread (DG_GetKey). Returns false when the queue is empty.
bool PopKey(int *pressed, unsigned char *key);

} // namespace input

#endif // DOOM4OH_OHOS_INPUT_H
