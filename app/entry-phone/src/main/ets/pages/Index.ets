import { common, Want } from '@kit.AbilityKit';
import { picker } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
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
  @State engineVersion: string = ''; // native library version, shown in the About section
  @State showSettings: boolean = false;
  @State wads: WadEntry[] = [];
  @State selectedPath: string = '';
  // Custom music soundfont: '' = bundled General MIDI (TimGM6mb.sf2), otherwise
  // the display name of the side-loaded files/soundfont.sf2 (e.g. a Roland SC-55).
  @State soundfontName: string = '';
  @State soundfontAvailable: boolean = false; // a custom soundfont file is present
  @State soundfontLabel: string = '';         // display label for the custom soundfont
  @State pendingActive: boolean = false; // a staged change awaits an engine restart
  @State pendingText: string = '';       // summary of the staged changes
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
      this.soundfontAvailable = vm.customAvailable();
      this.soundfontLabel = vm.customLabel();
      this.pendingActive = vm.hasPendingChanges();
      this.pendingText = vm.pendingSummary();
    });
    this.settingsVM = vm;
    vm.load();
  }

  /**
   * Resume the engine when the page becomes visible — but not while the settings
   * sheet is open (e.g. returning from the document picker), or the game would run
   * behind it. The close callback resumes when the sheet is dismissed.
   */
  onPageShow(): void {
    if (!this.showSettings) {
      this.gameVM.resume();
    }
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
      await vm.importWad(uris[0]);
    } catch (err) {
      hilog.error(0x0000, 'Doom4OH', 'WAD import failed: %{public}s', JSON.stringify(err));
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
      await vm.importSoundfont(uris[0]);
    } catch (err) {
      hilog.error(0x0000, 'Doom4OH', 'soundfont import failed: %{public}s', JSON.stringify(err));
    }
  }

  /** Switches to the bundled General MIDI (the custom file is kept). */
  private useBuiltinSoundfont(): void {
    this.settingsVM?.useBuiltinSoundfont();
  }

  /** Switches to the custom soundfont, when one is available. */
  private useCustomSoundfont(): void {
    this.settingsVM?.useCustomSoundfont();
  }

  /** Deletes the custom soundfont file and reverts to General MIDI. */
  private deleteCustomSoundfont(): void {
    if (this.settingsVM?.deleteCustomSoundfont() === false) {
      hilog.error(0x0000, 'Doom4OH', 'failed to remove the custom soundfont');
    }
  }

  /** Saves the selection and restarts the app so the engine reloads with it. */
  private applyAndRestart(): void {
    // Only restart once the settings are safely on disk — otherwise the restart
    // would drop the staged changes and reload the old ones.
    if (this.settingsVM?.persist() !== true) {
      hilog.error(0x0000, 'Doom4OH', 'save failed — settings not applied, not restarting');
      return;
    }
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
          const soundfontPath = this.settingsVM?.activeSoundfontPath() ?? '';
          const ok = this.gameVM.start(this.getCtx().resourceManager, this.getCtx().filesDir,
            this.selectedPath, soundfontPath);
          this.engineVersion = getDoomVersion();
          if (!ok) {
            hilog.error(0x0000, 'Doom4OH', 'engine failed to start');
          }
          this.armIdleTimer();
          this.gameVM.armQuitWatcher(() => {
            this.getCtx().terminateSelf();
          });
        })
      // Touch control overlay: dual sticks, FIRE, weapon switch, USE tap, menu buttons.
      GameControls({
        controlsOpacity: this.overlayOpacity,
        onOpenSettings: () => {
          this.ensureInit();
          this.settingsVM?.rescan();
          this.showSettings = true;
          this.gameVM.pause();
        }
      })
        // While the settings sheet is open the controls show through its margins;
        // disable them so a stray joystick/FIRE touch can't queue input for later.
        .enabled(!this.showSettings)

      if (this.showSettings) {
        SettingsSheet({
          wads: this.wads,
          selectedPath: this.selectedPath,
          soundfontName: this.soundfontName,
          soundfontAvailable: this.soundfontAvailable,
          soundfontLabel: this.soundfontLabel,
          hasPending: this.pendingActive,
          pendingSummary: this.pendingText,
          appVersion: this.engineVersion,
          onSelectWad: (path: string) => {
            this.settingsVM?.selectWad(path);
          },
          onDeleteWad: (path: string) => {
            this.settingsVM?.deleteWad(path);
          },
          onImportWad: () => {
            this.importWad();
          },
          onImportSoundfont: () => {
            this.importSoundfont();
          },
          onUseBuiltinSoundfont: () => {
            this.useBuiltinSoundfont();
          },
          onUseCustomSoundfont: () => {
            this.useCustomSoundfont();
          },
          onDeleteSoundfont: () => {
            this.deleteCustomSoundfont();
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
