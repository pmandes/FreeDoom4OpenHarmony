import { common, Want } from '@kit.AbilityKit';
import { picker } from '@kit.CoreFileKit';
import {
  DOOM_XCOMPONENT_LIBRARY,
  getDoomVersion,
  mapHardwareKey,
  pushDoomRawKey
} from 'doom';
import { WadEntry } from 'core';
import { GameViewModel } from '../viewmodel/GameViewModel';
import { SettingsViewModel } from '../viewmodel/SettingsViewModel';
import { SettingsSheet } from '../view/SettingsSheet';
import { GameControls } from '../view/GameControls';

/** Main game screen: composes the game surface, the control overlay, and settings. */
@Entry
@Component
struct Index {
  @State status: string = 'starting…';
  @State showSettings: boolean = false;
  @State wads: WadEntry[] = [];
  @State selectedPath: string = '';
  // Custom music soundfont: '' = bundled General MIDI (TimGM6mb.sf2), otherwise
  // the display name of the side-loaded files/soundfont.sf2 (e.g. a Roland SC-55).
  @State soundfontName: string = '';
  @State overlayOpacity: number = 1;
  private idleTimer: number = -1;

  /** Overlay fades after 10s without touch; any screen touch restores it smoothly. */
  private restoreOverlay(): void {
    if (this.overlayOpacity < 1) {
      this.getUIContext().animateTo({ duration: 200, curve: Curve.EaseOut }, () => {
        this.overlayOpacity = 1;
      });
    }
    this.armIdleTimer();
  }

  /** (Re)arms the 10s idle timer that fades the control overlay out. */
  private armIdleTimer(): void {
    if (this.idleTimer >= 0) {
      clearTimeout(this.idleTimer);
    }
    this.idleTimer = setTimeout(() => {
      this.idleTimer = -1;
      if (this.showSettings) {
        return; // panel open — keep controls visible
      }
      this.getUIContext().animateTo({ duration: 800, curve: Curve.EaseInOut }, () => {
        this.overlayOpacity = 0;
      });
    }, 10000);
  }

  // NOTE: property getters in ArkTS structs return undefined (verified on the
  // emulator) — hence plain methods, not "get" accessors.
  private getCtx(): common.UIAbilityContext {
    return getContext(this) as common.UIAbilityContext;
  }

  private initialized = false;
  private settingsVM?: SettingsViewModel;
  private gameVM: GameViewModel = new GameViewModel();

  // getHostContext() is unavailable before the UI is built (aboutToAppear
  // crashes with "context is invalid") — lazy init from onLoad/⚙ instead.
  private ensureInit(): void {
    if (this.initialized) {
      return;
    }
    this.initialized = true;
    const vm = new SettingsViewModel(this.getCtx().filesDir);
    // Mirror the view model's snapshot into @State so the panel re-renders.
    vm.setListener(() => {
      this.wads = vm.wads();
      this.selectedPath = vm.selection();
      this.soundfontName = vm.soundfontName();
    });
    this.settingsVM = vm;
    vm.load();
  }

  /** Resume the engine when the page becomes visible. */
  onPageShow(): void {
    this.gameVM.resume();
  }

  /** Pause the engine when the page is hidden. */
  onPageHide(): void {
    this.gameVM.pause();
  }

  /** Opens the document picker and imports the chosen WAD via the settings view model. */
  private async importWad(): Promise<void> {
    const vm = this.settingsVM;
    if (vm === undefined) {
      return;
    }
    try {
      const dvp = new picker.DocumentViewPicker(this.getCtx());
      const uris = await dvp.select({ maxSelectNumber: 1, fileSuffixFilters: ['WAD|.wad'] });
      if (!uris || uris.length === 0) {
        return;
      }
      this.status = `imported ${vm.importWad(uris[0])}`;
    } catch (err) {
      this.status = `import failed: ${JSON.stringify(err)}`;
    }
  }

  /**
   * Opens the document picker and imports the chosen SoundFont as the active custom
   * one; the engine prefers it over the bundled GM soundfont. Applies on restart.
   */
  private async importSoundfont(): Promise<void> {
    const vm = this.settingsVM;
    if (vm === undefined) {
      return;
    }
    try {
      const dvp = new picker.DocumentViewPicker(this.getCtx());
      const uris = await dvp.select({ maxSelectNumber: 1, fileSuffixFilters: ['SoundFont|.sf2'] });
      if (!uris || uris.length === 0) {
        return;
      }
      this.status = `soundfont: ${vm.importSoundfont(uris[0])}`;
    } catch (err) {
      this.status = `soundfont import failed: ${JSON.stringify(err)}`;
    }
  }

  /** Removes the custom soundfont so the engine falls back to the bundled GM one. */
  private removeSoundfont(): void {
    this.settingsVM?.removeSoundfont();
    this.status = 'soundfont: built-in';
  }

  /** Saves the selection and restarts the app so the engine reloads with it. */
  private applyAndRestart(): void {
    this.settingsVM?.persist();
    const want: Want = {
      bundleName: this.getCtx().abilityInfo.bundleName,
      abilityName: this.getCtx().abilityInfo.name,
    };
    try {
      this.getCtx().getApplicationContext().restartApp(want);
    } catch (err) {
      // restartApp can be restricted — terminating the app also forces a fresh start
      this.getCtx().terminateSelf();
    }
  }

  /** Composes the game surface, the control overlay, and the settings panel. */
  build() {
    Stack() {
      // Full-screen wallpaper behind the game — visible in the black bars on the
      // sides (320x200 doesn't fill landscape) and before the engine first draws.
      Image($r('app.media.doom_background'))
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Cover)

      // Landscape: height is the constraint; 320x200 (aspect 1.6) centered, with
      // black side bars taken up by the overlay buttons.
      XComponent({ id: 'doom_surface', type: XComponentType.SURFACE, libraryname: DOOM_XCOMPONENT_LIBRARY })
        .height('100%')
        .aspectRatio(1.6)
        .onLoad(() => {
          this.ensureInit();
          const ok = this.gameVM.start(this.getCtx().resourceManager, this.getCtx().filesDir, this.selectedPath);
          this.status = ok ? `native ${getDoomVersion()}` : 'START FAILED';
          this.armIdleTimer();
          this.gameVM.armQuitWatcher(() => {
            this.getCtx().terminateSelf();
          });
        })
      // Touch control overlay: dual sticks, FIRE, weapon switch, USE tap, menu buttons.
      GameControls({
        controlsOpacity: this.overlayOpacity,
        status: this.status,
        onOpenSettings: () => {
          this.ensureInit();
          this.settingsVM?.rescan();
          this.showSettings = true;
          this.gameVM.pause();
        }
      })

      if (this.showSettings) {
        SettingsSheet({
          wads: this.wads,
          selectedPath: this.selectedPath,
          soundfontName: this.soundfontName,
          onSelectWad: (path: string) => {
            this.settingsVM?.selectWad(path);
          },
          onImportWad: () => {
            this.importWad();
          },
          onImportSoundfont: () => {
            this.importSoundfont();
          },
          onRemoveSoundfont: () => {
            this.removeSoundfont();
          },
          onApply: () => {
            this.applyAndRestart();
          },
          onClose: () => {
            this.showSettings = false;
            this.gameVM.resume();
          }
        })
      }
    }
    .height('100%')
    .width('100%')
    .backgroundColor(Color.Black)
    .onTouch(() => {
      this.restoreOverlay(); // any screen touch: restore overlay + reset the timer
    })
    // Physical keyboard (USB on the phone, host keyboard in the emulator):
    // standard Doom mapping. Deliberately does NOT restore the overlay — playing
    // on the keyboard leaves a clean screen.
    .focusable(true)
    .defaultFocus(true)
    .onKeyEvent((event: KeyEvent) => {
      if (this.showSettings) {
        return; // characters go to the panel then
      }
      const code = mapHardwareKey(event.keyCode);
      if (code === 0) {
        return;
      }
      if (event.type === KeyType.Down) {
        pushDoomRawKey(code, true);
      } else if (event.type === KeyType.Up) {
        pushDoomRawKey(code, false);
      }
    })
  }
}
