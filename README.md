# FreeDoom4OpenHarmony

DOOM for **HarmonyOS** and **OpenHarmony** - phone and smartwatch. A port of
[doomgeneric](https://github.com/ozkl/doomgeneric) with a native C/NAPI platform
layer and an ArkTS/ArkUI touch overlay, shipping the free
[Freedoom](https://freedoom.github.io/) game data so it runs out of the box.

![Platform](https://img.shields.io/badge/platform-HarmonyOS%20%7C%20OpenHarmony-1f6feb)
![API](https://img.shields.io/badge/API-20%2B%20HarmonyOS%206.0%2B-1f6feb)
![Language](https://img.shields.io/badge/lang-ArkTS%20and%20C%2FC%2B%2B-orange)
![License](https://img.shields.io/badge/license-GPLv2-green)

| Phone (HarmonyOS) | Phone (Oniro) | Watch |
|---|---|---|
| ![Phone gameplay](assets/screenshot-mobile.png) | ![Oniro / OpenHarmony](assets/screenshot-openharmony.png) | ![Watch](assets/screenshot-watch.png) |

## Features

- **Two apps, one codebase** - a phone build and a Huawei Watch build sharing the
  same native engine and platform layer.
- **Runs out of the box** - bundles Freedoom (`freedoom1.wad`); no external WAD
  required. Custom IWADs can be imported.
- **Native rendering** - the 320x200 frame is presented through an XComponent
  `SURFACE` / `NativeWindow`, upscaled nearest-neighbor for a crisp,
  pixel-perfect image (no bilinear blur).
- **Sound and music** - SFX and MIDI music via OHAudio, with a TinySoundFont
  synthesizer driving the bundled `TimGM6mb.sf2` soundfont.
- **Touch controls** - a dual-stick overlay on the phone and a joystick plus
  tap-to-fire layout on the watch, plus full physical-keyboard support.
- **Auto-save** - save slots are named automatically (`E1M1 HH:MM DD/MM`), no
  on-screen keyboard needed.

## Repository layout

```
FreeDoom4OpenHarmony/
  mobile/   phone app (org.pmandes.fd4ohos.phone)
  watch/    watch app (org.pmandes.fd4ohos.watch)
```

Each subdirectory is a **standalone Hvigor / DevEco Studio project** (`entry` UI
module plus `doom` native module). Open `mobile/` or `watch/` as the project
root, not the repository root.

## Requirements

- [DevEco Studio](https://developer.huawei.com/consumer/en/deveco-studio/) 5.1.1+
  or the matching DevEco Command Line Tools
- [DevEco CLI](https://gitcode.com/openharmony-sig/deveco-cli) - wraps the DevEco
  toolchain (build, run, device control, emulators, logging) into a single `devecocli`
  command; used for the command-line builds below
- HarmonyOS / OpenHarmony SDK, API 20 (6.0.0) or newer
  (mobile targets 6.0.2 / API 22, watch targets 6.1.0 / API 23)
- `hdc` (bundled with the SDK) for deployment
- A device or emulator: HarmonyOS phone / Huawei Watch, or an Oniro / OpenHarmony 6.x device

## Build and run

Each app is a standard Hvigor project. Build it from DevEco Studio or entirely
from the command line.

### With DevEco Studio

1. Open **`mobile/`** (or **`watch/`**) as the project.
2. **Configure signing** in File > Project Structure > Signing Configs
   (`signingConfigs` is intentionally empty in this repo; automatic signing needs
   a Huawei developer account, a debug / self-signed profile is fine for local
   devices).
3. Press Run, or Build > Build Hap(s).

### From the command line (no IDE)

You need the SDK and the bundled command-line tools (`node`, `ohpm`, `hvigor`,
`hdc`) that ship with DevEco Studio or the DevEco Command Line Tools. Point
`DEVECO_SDK_HOME` at the SDK first:

```
# bash
export DEVECO_SDK_HOME="<DevEco Studio>/sdk"
# PowerShell
$env:DEVECO_SDK_HOME = "<DevEco Studio>\sdk"
```

**Option A - devecocli** (the tool used to produce the tested builds):

```
cd mobile
devecocli build --product default --build-mode debug
```

**Option B - Hvigor directly** (the underlying build system). Add the bundled
tools under `<DevEco Studio>/tools/` (`node`, `ohpm/bin`, `hvigor/bin`) to PATH,
then:

```
cd mobile
ohpm install
hvigor assembleHap --mode module -p product=default -p buildMode=debug --no-daemon
```

The `hvigorw` wrapper is not committed; use the bundled `hvigor`, or let DevEco
generate the wrapper once.

Both produce the HAP at
`entry/build/default/outputs/default/entry-default-signed.hap` (a signing config
must be set, see above). Use `--build-mode release` / `buildMode=release` for a
release build.

### Native layer only (NDK + CMake)

Hvigor compiles the C/C++ engine and platform layer for you. To build
`libdoom.so` on its own against the OpenHarmony NDK toolchain:

```
cmake -G Ninja -S doom/src/main/cpp -B build-native \
  -DOHOS_ARCH=arm64-v8a -DOHOS_STL=c++_shared \
  -DCMAKE_TOOLCHAIN_FILE="$DEVECO_SDK_HOME/default/openharmony/native/build/cmake/ohos.toolchain.cmake"
cmake --build build-native
```

Packaging the full HAP still goes through Hvigor / devecocli.

### Deploy

```
hdc -t <device> install -r entry/build/default/outputs/default/entry-default-signed.hap
hdc -t <device> shell aa start -b org.pmandes.fd4ohos.phone -a EntryAbility
```

The phone HAP also installs and runs on **Oniro / OpenHarmony 6.x** devices
(tested on the Volla Phone X23).

## Controls

**Phone** (landscape):

- **Left stick** - move (forward / back, strafe left / right)
- **Right stick** - turn left / right
- **Fire button** (red) - shoot (also confirms menus)
- **Weapon buttons** (arrows) - next / previous weapon
- **Tap the screen** - use (open doors, flip switches)
- **Settings button** and **menu button** (menu = Escape)

**Watch:**

- **Joystick** - move
- **Rotate the crown** - turn
- **Tap the screen** - fire / use / confirm
- **Weapon buttons** (triangles) - change weapon
- **Settings button** and **menu button** (menu = Escape)

A USB / Bluetooth keyboard works on both (arrows, Ctrl = fire, Space = use,
number keys = weapons, Esc = menu, and so on).

## Game data (WADs)

The apps ship Freedoom Phase 1 (`freedoom1.wad`) and start with it by default.
You can supply your own IWAD:

- **Phone** - import a `.wad` from device storage via the settings screen.
- **Watch** - download a WAD over the network from the settings screen.

Only DOOM-engine IWADs are supported (Freedoom, DOOM / DOOM II). Heretic, Hexen
and Strife are not.

## Tested devices

| Device | OS | Status |
|---|---|---|
| Huawei Pura 70 | HarmonyOS 6.0.2 | Working |
| Huawei Watch 5 | HarmonyOS (wearable) | Working |
| Volla Phone X23 | Oniro / OpenHarmony 6.1.0 (API 23) | Working |

## Credits and acknowledgements

- **DOOM** (c) id Software - original source released under the GPL.
- **[doomgeneric](https://github.com/ozkl/doomgeneric)** by ozkl - the portable
  DOOM core this port builds on.
- **[Freedoom](https://freedoom.github.io/)** - free, BSD-licensed game data.
- **[TinySoundFont](https://github.com/schellingb/TinySoundFont)** - MIDI synthesis.
- **TimGM6mb** - the bundled General MIDI soundfont, by Tim Brechbill and
  David Bolton (GPLv2).

## License

The engine and platform code are licensed under the **GNU General Public License
v2** (inherited from the DOOM source via doomgeneric); see [LICENSE](LICENSE).

Freedoom game data (`freedoom1.wad`) is distributed under the Freedoom
[BSD 3-Clause license](https://github.com/freedoom/freedoom/blob/master/COPYING.adoc).
The bundled `TimGM6mb.sf2` soundfont (Tim Brechbill, 2004; David Bolton, 2010)
is licensed under the GNU General Public License v2 - the author notes that some
samples are public domain and the rest fall under the GPL, so the packaged
soundfont is distributed as GPLv2.

> DOOM is a trademark of id Software LLC. This is an unofficial, non-commercial
> fan port and is not affiliated with or endorsed by id Software or Huawei.
