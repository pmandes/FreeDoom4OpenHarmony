import { common, Want } from '@kit.AbilityKit';
import { DOOM_XCOMPONENT_LIBRARY, DoomAction, pushDoomKey } from 'doom';
import { WadEntry } from 'core';
import { DownloadableWad } from '../service/WadDownloader';
import { WatchGameViewModel } from '../viewmodel/WatchGameViewModel';
import { WatchSettingsViewModel } from '../viewmodel/WatchSettingsViewModel';
import { WatchControls } from '../view/WatchControls';
import { WatchSettingsSheet } from '../view/WatchSettingsSheet';

// Huawei Watch 5: round 466x466 screen. A rectangle with the game's aspect
// ratio (1.6 for 320x200) inscribed in a circle of diameter d has width
// d*1.6/sqrt(1+1.6^2) = 0.848*d and height 0.53*d (~395x247 px).
const GAME_WIDTH_PERCENT = '84.8%';

/** Watch game screen: composes the game surface, the control overlay, and settings. */
@Entry
@Component
struct Index {
  @State showSettings: boolean = false;
  // Settings snapshot mirrored from the view model (the overlay reads these).
  @State wads: WadEntry[] = [];
  @State selectedPath: string = '';
  @State deletePath: string = '';
  @State downloadMode: boolean = false;
  @State downloadingFile: string = '';
  @State downloadPct: number = 0;
  // Crown turning is a root-level event (needs focus), so its state stays here.
  private crownDir = 0;
  private crownTimer = -1;
  private initialized = false;
  private settingsVM?: WatchSettingsViewModel;
  private gameVM: WatchGameViewModel = new WatchGameViewModel();

  /** Resumes the game loop when the page becomes visible. */
  onPageShow(): void {
    this.gameVM.resume();
  }

  /** Pauses the game loop when the page is hidden. */
  onPageHide(): void {
    this.gameVM.pause();
  }

  // ArkTS struct getters return undefined - hence this method.
  private getCtx(): common.UIAbilityContext {
    return getContext(this) as common.UIAbilityContext;
  }

  /** Builds the settings view model and mirrors its snapshot into @State (once). */
  private ensureInit(): void {
    if (this.initialized) {
      return;
    }
    this.initialized = true;
    const vm = new WatchSettingsViewModel(this.getCtx().filesDir);
    vm.setListener(() => {
      this.wads = vm.wads();
      this.selectedPath = vm.selection();
      this.deletePath = vm.armedForDelete();
      this.downloadMode = vm.isDownloadMode();
      this.downloadingFile = vm.downloadingZip();
      this.downloadPct = vm.downloadPercent();
    });
    this.settingsVM = vm;
    vm.load();
  }

  /** Pauses the game and opens the settings overlay. */
  private openSettings(): void {
    this.ensureInit();
    this.gameVM.pause();
    this.settingsVM?.rescan();
    this.showSettings = true;
  }

  /** Saves settings and restarts the app so the new IWAD takes effect. */
  private applyAndRestart(): void {
    this.settingsVM?.persist();
    const want: Want = {
      bundleName: this.getCtx().abilityInfo.bundleName,
      abilityName: this.getCtx().abilityInfo.name,
    };
    try {
      this.getCtx().getApplicationContext().restartApp(want);
    } catch (err) {
      this.getCtx().terminateSelf();
    }
  }

  /**
   * Second layer of protection against accidental exit: if a back event still
   * gets through (e.g. a gesture not covered by setGestureBackEnabled), consume it.
   */
  onBackPress(): boolean {
    return true;
  }

  /** Fires a momentary key press (down, then up after 60 ms) for the surface taps. */
  private tapKey(action: DoomAction): void {
    pushDoomKey(action, true);
    setTimeout(() => {
      pushDoomKey(action, false);
    }, 60);
  }

  /** Releases the crown turn + run keys and clears the current direction. */
  private releaseCrown(): void {
    if (this.crownDir > 0) {
      pushDoomKey(DoomAction.Right, false);
    } else if (this.crownDir < 0) {
      pushDoomKey(DoomAction.Left, false);
    }
    if (this.crownDir !== 0) {
      pushDoomKey(DoomAction.Run, false);
    }
    this.crownDir = 0;
  }

  /**
   * Turning the crown holds the turn key + run (RSHIFT doubles the vanilla turn
   * speed). A long timeout keeps the hold continuous - the engine has a slow turn
   * phase for the first ~6 tics, so every release resets turn acceleration.
   */
  private handleCrown(event: CrownEvent): void {
    if (event.action === CrownAction.END) {
      if (this.crownTimer >= 0) {
        clearTimeout(this.crownTimer);
        this.crownTimer = -1;
      }
      this.releaseCrown();
      return;
    }
    const dir = event.angularVelocity > 0 ? 1 : (event.angularVelocity < 0 ? -1 : 0);
    if (dir === 0) {
      return;
    }
    if (dir !== this.crownDir) {
      this.releaseCrown();
      pushDoomKey(DoomAction.Run, true);
      pushDoomKey(dir > 0 ? DoomAction.Right : DoomAction.Left, true);
      this.crownDir = dir;
    }
    if (this.crownTimer >= 0) {
      clearTimeout(this.crownTimer);
    }
    this.crownTimer = setTimeout(() => {
      this.crownTimer = -1;
      this.releaseCrown();
    }, 450);
  }

  /** Builds the game UI: background, XComponent surface, controls, and settings overlay. */
  build() {
    Stack() {
      // App background - the doom-background image (a round composition fitted
      // to the dial); visible around the game rectangle.
      Image($r('app.media.doom_background'))
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Cover)

      XComponent({ id: 'doom_surface', type: XComponentType.SURFACE, libraryname: DOOM_XCOMPONENT_LIBRARY })
        .width(GAME_WIDTH_PERCENT)
        .aspectRatio(1.6)
        .onLoad(() => {
          this.ensureInit();
          const ctx = this.getCtx();
          this.gameVM.start(ctx.resourceManager, ctx.filesDir, this.selectedPath);
          this.gameVM.armQuitWatcher(() => {
            this.getCtx().terminateSelf();
          });
        })
        // Tap = fire + use + confirm (ENTER also acts as "Y", because
        // key_menu_confirm is rebound to ENTER in the native layer).
        // Note: onClick on an XComponent SURFACE never fires - only .gesture() works.
        .gesture(TapGesture().onAction(() => {
          this.tapKey(DoomAction.Fire);
          this.tapKey(DoomAction.Use);
          this.tapKey(DoomAction.Enter);
        }))
        // Long-press = ESC (menu access - start game, save, options).
        .gesture(LongPressGesture({ duration: 450 }).onAction(() => {
          this.tapKey(DoomAction.Escape);
        }))

      // On-screen controls overlay: joystick, weapon switch, gear/menu buttons.
      WatchControls({
        onOpenSettings: () => {
          this.openSettings();
        }
      })

      if (this.showSettings) {
        WatchSettingsSheet({
          wads: this.wads,
          selectedPath: this.selectedPath,
          deletePath: this.deletePath,
          downloadMode: this.downloadMode,
          downloadingFile: this.downloadingFile,
          downloadPct: this.downloadPct,
          onSelectWad: (path: string) => {
            this.settingsVM?.selectWad(path);
          },
          onArmDelete: (path: string) => {
            this.settingsVM?.armDelete(path);
          },
          onDownload: (item: DownloadableWad) => {
            this.settingsVM?.download(item);
          },
          onEnterDownload: () => {
            this.settingsVM?.enterDownloadMode();
          },
          onExitDownload: () => {
            this.settingsVM?.exitDownloadMode();
          },
          onCancelDelete: () => {
            this.settingsVM?.cancelDelete();
          },
          onConfirmDelete: () => {
            this.settingsVM?.confirmDelete();
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

      // Crown: turn left/right (requires focus on the root component).
    }
    .height('100%')
    .width('100%')
    .backgroundColor(Color.Black)
    .focusable(true)
    .defaultFocus(true)
    .onDigitalCrown((event: CrownEvent) => {
      this.handleCrown(event);
    })
  }
}
