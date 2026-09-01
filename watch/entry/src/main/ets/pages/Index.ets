import { common, Want } from '@kit.AbilityKit';
import { ArcList, ArcListItem, ArcScrollBar } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { http } from '@kit.NetworkKit';
import { zlib } from '@kit.BasicServicesKit';
import {
  DOOM_XCOMPONENT_LIBRARY,
  DoomAction,
  pauseDoom,
  pushDoomKey,
  resumeDoom,
  startDoom
} from 'doom';

/** A selectable IWAD slot in the settings list. */
interface WadEntry {
  name: string;  // display title (for the built-in / mapped from the file)
  path: string;  // '' = built-in Freedoom
}

/** Persisted user settings (settings.json). */
interface Settings {
  iwad?: string;
}

/** A WAD available for download as a ZIP from the remote repo. */
interface DownloadableWad {
  zip: string;   // ZIP file name in the repo (with spaces)
  label: string; // display title of the game
  mb: number;
}

// WADs available for download as ZIPs (dabignerd/doom-wads repo), unpacked on
// the watch into the sandbox. Only DOOM-engine IWADs (Freedoom included) -
// Heretic/Hexen/Strife/Chex3 have their own engines and doomgeneric won't run them.
const WAD_ZIP_BASE = 'https://raw.githubusercontent.com/dabignerd/doom-wads/master/zips/';
const DOWNLOADABLE_WADS: DownloadableWad[] = [
  { zip: 'Freedoom - Phase 1 (v0.12.1).zip', label: 'Freedoom: Phase 1', mb: 9 },
  { zip: 'Freedoom - Phase 2 (v0.12.1).zip', label: 'Freedoom: Phase 2', mb: 10 },
  { zip: 'The Ultimate Doom.zip', label: 'The Ultimate Doom', mb: 5 },
  { zip: 'Doom (v1.9).zip', label: 'Doom', mb: 5 },
  { zip: 'Doom II - Hell on Earth (v1.9).zip', label: 'Doom II: Hell on Earth', mb: 6 },
  { zip: 'Final Doom - The Plutonia Experiment.zip', label: 'Final Doom: Plutonia', mb: 7 },
  { zip: 'Final Doom - TNT - Evilution.zip', label: 'Final Doom: TNT Evilution', mb: 8 },
  { zip: 'Chex Quest.zip', label: 'Chex Quest', mb: 4 },
];

// Map from raw WAD file name -> display title (slot list).
const WAD_TITLES: Record<string, string> = {
  'freedoom1.wad': 'Freedoom: Phase 1',
  'freedoom2.wad': 'Freedoom: Phase 2',
  'doom.wad': 'The Ultimate Doom',
  'doomu.wad': 'The Ultimate Doom',
  'doom1.wad': 'Doom (shareware)',
  'doom2.wad': 'Doom II: Hell on Earth',
  'plutonia.wad': 'Final Doom: Plutonia',
  'tnt.wad': 'Final Doom: TNT Evilution',
  'chex.wad': 'Chex Quest',
};

/** Returns the display title for a WAD file name, or the name itself if unknown. */
function wadTitle(fileName: string): string {
  return WAD_TITLES[fileName.toLowerCase()] ?? fileName;
}


// Huawei Watch 5: round 466x466 screen. A rectangle with the game's aspect
// ratio (1.6 for 320x200) inscribed in a circle of diameter d has width
// d*1.6/sqrt(1+1.6^2) = 0.848*d and height 0.53*d (~395x247 px).
const GAME_WIDTH_PERCENT = '84.8%';

// Analog joystick (bottom center): ring + draggable knob.
const JOY_SIZE = 60;
const KNOB_SIZE = 24;
const JOY_MAX = (JOY_SIZE - KNOB_SIZE) / 2; // max knob travel
const JOY_TH = 9; // axis trigger threshold (dead zone)

@Entry
@Component
struct Index {
  @State knobX: number = 0;
  @State knobY: number = 0;
  @State showSettings: boolean = false;
  @State downloadMode: boolean = false;
  @State downloadingFile: string = '';
  @State downloadPct: number = 0;
  @State wads: WadEntry[] = [];
  @State selectedPath: string = '';
  @State deletePath: string = ''; // '' = not in delete mode; otherwise the path to delete
  private joyUp = false;
  private joyDown = false;
  private joyLeft = false;
  private joyRight = false;
  private crownDir = 0;
  private crownTimer = -1;
  private initialized = false;
  private listScroller: Scroller = new Scroller(); // shared by both lists (only one visible at a time)

  /** Resumes the game loop when the page becomes visible. */
  onPageShow(): void {
    resumeDoom();
  }

  /** Pauses the game loop when the page is hidden. */
  onPageHide(): void {
    pauseDoom();
  }

  // ArkTS struct getters return undefined - hence these methods.
  private getCtx(): common.UIAbilityContext {
    return getContext(this) as common.UIAbilityContext;
  }

  private getWadsDir(): string {
    return this.getCtx().filesDir + '/wads';
  }

  private getSettingsPath(): string {
    return this.getCtx().filesDir + '/settings.json';
  }

  /** Loads persisted settings and the WAD list once, on first use. */
  private ensureInit(): void {
    if (this.initialized) {
      return;
    }
    this.initialized = true;
    try {
      const txt = fs.readTextSync(this.getSettingsPath());
      const s = JSON.parse(txt) as Settings;
      this.selectedPath = s.iwad ?? '';
    } catch (err) {
      this.selectedPath = '';
    }
    this.refreshWads();
  }

  /** Persists the current IWAD selection to settings.json. */
  private saveSettings(): void {
    try {
      const file = fs.openSync(this.getSettingsPath(),
        fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      const s: Settings = { iwad: this.selectedPath };
      fs.writeSync(file.fd, JSON.stringify(s));
      fs.closeSync(file);
    } catch (err) {
      hilog.error(0x0000, 'Doom4OH', 'saveSettings failed: %{public}s', JSON.stringify(err));
    }
  }

  /** Appends every .wad found in dir to entries (deduplicated by path). */
  private scanDirForWads(dir: string, entries: WadEntry[]): void {
    try {
      const files = fs.listFileSync(dir).filter((f: string) => f.toLowerCase().endsWith('.wad')).sort();
      hilog.info(0x0000, 'Doom4OH', 'scan OK %{public}s -> %{public}d wad', dir, files.length);
      for (const f of files) {
        const path = `${dir}/${f}`;
        if (!entries.some((e: WadEntry) => e.path === path)) {
          entries.push({ name: wadTitle(f), path: path });
        }
      }
    } catch (err) {
      hilog.info(0x0000, 'Doom4OH', 'scan FAIL %{public}s : %{public}s', dir, JSON.stringify(err));
    }
  }

  /** Rebuilds the WAD slot list (built-in + scanned sandbox files). */
  private refreshWads(): void {
    try {
      fs.mkdirSync(this.getWadsDir());
    } catch (err) {
      // already exists - OK
    }
    const entries: WadEntry[] = [{ name: 'Freedoom (built-in)', path: '' }];
    this.scanDirForWads(this.getWadsDir(), entries);
    this.wads = entries;
    if (this.selectedPath !== '' && !entries.some((e: WadEntry) => e.path === this.selectedPath)) {
      this.selectedPath = '';
    }
  }

  /**
   * Downloads a WAD ZIP (streamed to a file), unpacks it via zlib and moves the
   * .wad into the sandbox at files/wads/. The INTERNET permission is system_grant.
   */
  private async downloadWad(item: DownloadableWad): Promise<void> {
    if (this.downloadingFile !== '') {
      return;
    }
    this.downloadingFile = item.zip;
    this.downloadPct = 0;
    const tmpDir = `${this.getCtx().filesDir}/dltmp`;
    const zipPath = `${tmpDir}/dl.zip`;
    const unzipDir = `${tmpDir}/out`;
    const request = http.createHttp();
    let file: fs.File | undefined;
    try {
      try { fs.rmdirSync(tmpDir); } catch (e) {}
      fs.mkdirSync(tmpDir);
      fs.mkdirSync(unzipDir);
      file = fs.openSync(zipPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      const fd = file.fd;
      request.on('dataReceive', (chunk: ArrayBuffer) => {
        fs.writeSync(fd, chunk);
      });
      request.on('dataReceiveProgress', (p: http.DataReceiveProgressInfo) => {
        if (p.totalSize > 0) {
          this.downloadPct = Math.floor(p.receiveSize * 90 / p.totalSize); // 90% = download
        }
      });
      const url = WAD_ZIP_BASE + encodeURIComponent(item.zip);
      const code = await request.requestInStream(url, {
        method: http.RequestMethod.GET, connectTimeout: 30000, readTimeout: 180000,
      });
      fs.closeSync(file);
      file = undefined;
      if (code < 200 || code >= 300) {
        hilog.error(0x0000, 'Doom4OH', 'download http %{public}d', code);
        return;
      }
      this.downloadPct = 92; // unpacking
      await zlib.decompressFile(zipPath, unzipDir);
      const wadName = this.findWad(unzipDir);
      if (wadName === '') {
        hilog.error(0x0000, 'Doom4OH', 'no wad in zip %{public}s', item.zip);
        return;
      }
      const dest = `${this.getWadsDir()}/${wadName}`;
      const src = fs.openSync(this.foundWadPath, fs.OpenMode.READ_ONLY);
      const out = fs.openSync(dest, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fs.copyFileSync(src.fd, out.fd);
      fs.closeSync(src);
      fs.closeSync(out);
      hilog.info(0x0000, 'Doom4OH', 'installed %{public}s from %{public}s', wadName, item.zip);
      this.selectedPath = dest;
      this.downloadMode = false;
      this.refreshWads();
    } catch (err) {
      hilog.error(0x0000, 'Doom4OH', 'download failed: %{public}s', JSON.stringify(err));
      if (file !== undefined) {
        try { fs.closeSync(file); } catch (e) {}
      }
    } finally {
      request.off('dataReceive');
      request.off('dataReceiveProgress');
      request.destroy();
      try { fs.rmdirSync(tmpDir); } catch (e) {}
      this.downloadingFile = '';
      this.downloadPct = 0;
    }
  }

  /** Deletes a downloaded WAD (sandbox only; the built-in Freedoom is skipped). */
  private confirmDelete(): void {
    const path = this.deletePath;
    this.deletePath = '';
    if (path === '') {
      return;
    }
    try {
      fs.unlinkSync(path);
      hilog.info(0x0000, 'Doom4OH', 'deleted %{public}s', path);
    } catch (err) {
      hilog.error(0x0000, 'Doom4OH', 'delete failed: %{public}s', JSON.stringify(err));
    }
    if (this.selectedPath === path) {
      this.selectedPath = ''; // removed selection falls back to Freedoom
    }
    this.refreshWads();
  }

  private foundWadPath: string = '';

  /** Finds the first .wad in the unpacked tree (one directory level deep). */
  private findWad(dir: string): string {
    try {
      const items = fs.listFileSync(dir);
      for (const it of items) {
        if (it.toLowerCase().endsWith('.wad')) {
          this.foundWadPath = `${dir}/${it}`;
          return it;
        }
      }
      for (const it of items) {
        const sub = `${dir}/${it}`;
        try {
          if (fs.statSync(sub).isDirectory()) {
            const inner = fs.listFileSync(sub).find((f: string) => f.toLowerCase().endsWith('.wad'));
            if (inner !== undefined) {
              this.foundWadPath = `${sub}/${inner}`;
              return inner;
            }
          }
        } catch (e) {}
      }
    } catch (err) {
      hilog.error(0x0000, 'Doom4OH', 'findWad err: %{public}s', JSON.stringify(err));
    }
    return '';
  }

  /** Pauses the game and opens the settings overlay. */
  private openSettings(): void {
    this.ensureInit();
    pauseDoom();
    this.refreshWads();
    this.showSettings = true;
  }

  /** Saves settings and restarts the app so the new IWAD takes effect. */
  private applyAndRestart(): void {
    this.saveSettings();
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

  /** Sends a key event only when the pressed state changed; returns the new state. */
  private setJoyKey(action: DoomAction, pressed: boolean, current: boolean): boolean {
    if (pressed !== current) {
      pushDoomKey(action, pressed);
    }
    return pressed;
  }

  /** Knob Y axis = forward/back, X axis = strafe (no turning - that's the crown). */
  private handleJoystick(event: TouchEvent): void {
    if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      this.knobX = 0;
      this.knobY = 0;
      this.joyUp = this.setJoyKey(DoomAction.Up, false, this.joyUp);
      this.joyDown = this.setJoyKey(DoomAction.Down, false, this.joyDown);
      this.joyLeft = this.setJoyKey(DoomAction.StrafeLeft, false, this.joyLeft);
      this.joyRight = this.setJoyKey(DoomAction.StrafeRight, false, this.joyRight);
      return;
    }
    const t = event.touches[0];
    if (t === undefined) {
      return;
    }
    let dx = t.x - JOY_SIZE / 2;
    let dy = t.y - JOY_SIZE / 2;
    const len = Math.sqrt(dx * dx + dy * dy);
    if (len > JOY_MAX) {
      dx = dx * JOY_MAX / len;
      dy = dy * JOY_MAX / len;
    }
    this.knobX = dx;
    this.knobY = dy;
    this.joyUp = this.setJoyKey(DoomAction.Up, dy < -JOY_TH, this.joyUp);
    this.joyDown = this.setJoyKey(DoomAction.Down, dy > JOY_TH, this.joyDown);
    this.joyLeft = this.setJoyKey(DoomAction.StrafeLeft, dx < -JOY_TH, this.joyLeft);
    this.joyRight = this.setJoyKey(DoomAction.StrafeRight, dx > JOY_TH, this.joyRight);
  }

  /** Fires a momentary key press (down, then up after 60 ms). */
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
          startDoom(ctx.resourceManager, ctx.filesDir, this.selectedPath);
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

      Column() {
        Row({ space: 16 }) {
          // Triangular weapon switchers (fallback for the dagger button):
          // styled like the joystick ring - outline + more transparent fill.
          Polygon({ width: 34, height: 34 })
            .points([[30, 3], [30, 31], [4, 17]])
            .fill('#12FFFFFF')
            .stroke('#33FFFFFF')
            .strokeWidth(1.5)
            .onClick(() => {
              this.tapKey(DoomAction.PrevWeapon);
            })

          Stack() {
            Circle()
              .width(JOY_SIZE)
              .height(JOY_SIZE)
              .fill('#1AFFFFFF')
              .stroke('#33FFFFFF')
              .strokeWidth(1.5)
            Circle()
              .width(KNOB_SIZE)
              .height(KNOB_SIZE)
              .fill('#59FFFFFF')
              .offset({ x: this.knobX, y: this.knobY })
          }
          .width(JOY_SIZE)
          .height(JOY_SIZE)
          .onTouch((event: TouchEvent) => {
            this.handleJoystick(event);
          })

          Polygon({ width: 34, height: 34 })
            .points([[4, 3], [4, 31], [30, 17]])
            .fill('#12FFFFFF')
            .stroke('#33FFFFFF')
            .strokeWidth(1.5)
            .onClick(() => {
              this.tapKey(DoomAction.NextWeapon);
            })
        }
        .alignItems(VerticalAlign.Center)
        .hitTestBehavior(HitTestMode.None) // the Row itself passes touches through; children catch them
        .margin({ bottom: 6 })
      }
      .height('100%')
      .width('100%')
      .justifyContent(FlexAlign.End)
      .alignItems(HorizontalAlign.Center)
      .hitTestBehavior(HitTestMode.None) // wrapper passes touches through, only children catch them

      // Top center: gear (WAD selection) + ESC (menu) - both round 40vp.
      Column() {
        Row({ space: 10 }) {
          Text('⚙')
            .width(40)
            .height(40)
            .fontSize(20)
            .fontColor('#73FFFFFF')
            .textAlign(TextAlign.Center)
            .backgroundColor('#1AFFFFFF')
            .borderRadius(20)
            .border({ width: 1, color: '#33FFFFFF' })
            .onClick(() => {
              this.openSettings();
            })
          Text('≡')
            .width(40)
            .height(40)
            .fontSize(22)
            .fontColor('#73FFFFFF')
            .textAlign(TextAlign.Center)
            .backgroundColor('#1AFFFFFF')
            .borderRadius(20)
            .border({ width: 1, color: '#33FFFFFF' })
            .onClick(() => {
              this.tapKey(DoomAction.Escape);
            })
        }
      }
      .height('100%')
      .width('100%')
      .justifyContent(FlexAlign.Start)
      .alignItems(HorizontalAlign.Center)
      .padding({ top: 12 })
      .hitTestBehavior(HitTestMode.None)

      if (this.showSettings) {
        Stack({ alignContent: Alignment.Bottom }) {
          // Full-height arc list - it goes UNDER the header so that ArcScrollBar
          // matches the curvature of the whole circle (tele4watch pattern: default
          // scrollBar off, dedicated arc bar on the right).
          if (true) {
            if (this.downloadMode) {
              Stack() {
              ArcList({ scroller: this.listScroller, initialIndex: 0 }) {
                ForEach(DOWNLOADABLE_WADS, (d: DownloadableWad) => {
                  ArcListItem() {
                    Button() {
                      Column({ space: 1 }) {
                        Text(this.downloadingFile === d.zip ? `${d.label}  ${this.downloadPct}%` : d.label)
                          .fontSize(12)
                          .fontWeight(FontWeight.Medium)
                          .fontColor('#E6FFFFFF')
                          .maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                        Text(this.downloadingFile === d.zip ? 'installing…' : `${d.mb} MB`)
                          .fontSize(9)
                          .fontColor('#80FFFFFF')
                      }
                      .justifyContent(FlexAlign.Center)
                      .padding({ left: 12, right: 12 })
                    }
                    .width('82%')
                    .height(40)
                    .borderRadius(20)
                    .linearGradient({
                      direction: GradientDirection.RightBottom,
                      colors: this.downloadingFile === d.zip
                        ? [['#2A8FB8', 0.0], ['#12466B', 1.0]]
                        : [['#3A3A3A', 0.0], ['#1E1E1E', 1.0]]
                    })
                    .opacity(this.downloadingFile !== '' && this.downloadingFile !== d.zip ? 0.4 : 0.9)
                    .onClick(() => {
                      this.downloadWad(d);
                    })
                  }
                  .margin({ top: 2, bottom: 2 })
                }, (d: DownloadableWad) => d.zip)
              }
              .width('100%')
              .height('100%')
              .scrollBar(BarState.Off)
              ArcScrollBar({ scroller: this.listScroller, state: BarState.Auto })
              }
              .width('100%')
              .height('100%')
            } else {
              Stack() {
              ArcList({ scroller: this.listScroller, initialIndex: 0 }) {
                ForEach(this.wads, (w: WadEntry) => {
                  ArcListItem() {
                    Button() {
                      Row({ space: 6 }) {
                        if ((this.deletePath !== '' && this.deletePath === w.path)) {
                          Text('🗑')
                            .fontSize(14)
                        }
                        Text(w.name)
                          .fontSize(12)
                          .fontWeight(FontWeight.Medium)
                          .fontColor((this.deletePath !== '' && this.deletePath === w.path)
                            ? '#FF6B6B'
                            : (this.selectedPath === w.path ? '#FFC93C' : '#E6FFFFFF'))
                          .maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                          .layoutWeight(1)
                          .textAlign(TextAlign.Center)
                        if (this.selectedPath === w.path && this.deletePath === '') {
                          Text('✓').fontSize(12).fontColor('#FFC93C')
                        }
                      }
                      .justifyContent(FlexAlign.Center)
                      .padding({ left: 14, right: 14 })
                    }
                    .width('82%')
                    .height(38)
                    .borderRadius(19)
                    .linearGradient({
                      direction: GradientDirection.RightBottom,
                      colors: (this.deletePath !== '' && this.deletePath === w.path)
                        ? [['#7A2E2E', 0.0], ['#4A1616', 1.0]]
                        : (this.selectedPath === w.path
                          ? [['#8A6A1F', 0.0], ['#5C4610', 1.0]]
                          : [['#3A3A3A', 0.0], ['#242424', 1.0]])
                    })
                    .opacity(0.92)
                    .onClick(() => {
                      if (this.deletePath === '') {
                        this.selectedPath = w.path;
                      }
                    })
                    // Long-press on a downloaded WAD (not the built-in) = delete mode.
                    .gesture(LongPressGesture({ duration: 500 }).onAction(() => {
                      if (w.path !== '') {
                        this.deletePath = w.path;
                      }
                    }))
                  }
                  .margin({ top: 2, bottom: 2 })
                }, (w: WadEntry) => w.path + w.name)
              }
              .width('100%')
              .height('100%')
              .scrollBar(BarState.Off)
              ArcScrollBar({ scroller: this.listScroller, state: BarState.Auto })
              }
              .width('100%')
              .height('100%')
            }
          }

          // Header as an overlay at the top edge (it doesn't take height from the
          // list - so ArcList stays at 100% and the scroll keeps its curvature).
          Column() {
            Text(this.downloadMode ? 'Download WAD' : 'Select IWAD')
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor(Color.White)
              .padding({ left: 16, right: 16, top: 5, bottom: 5 })
              .backgroundColor('#CC0A0A0A')
              .borderRadius(14)
              .margin({ top: 14 })
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Start)
          .hitTestBehavior(HitTestMode.None)

          // Round action buttons floating over the list - pattern from the
          // Telegram 4 watch CallScreen. Arranged along an arc (sides raised =
          // "smile") so left/right don't stick out past the round screen at the bottom.
          Row({ space: this.downloadMode ? 28 : 18 }) {
            // ✕ / back - raised along the arc in slot mode; inline in Download.
            Button({ type: ButtonType.Circle }) {
              Text('×')
                .fontSize(30)
                .fontWeight(FontWeight.Bold)
                .fontColor('#F2FFFFFF')
            }
            .width(54)
            .height(54)
            .borderRadius(27)
            .linearGradient({
              direction: GradientDirection.Bottom,
              colors: [['#E5544F', 0.0], ['#A62823', 1.0]]
            })
            .opacity(0.82)
            .border({ width: 1, color: '#33FFFFFF' })
            .shadow({ color: '#59000000', radius: 12, offsetX: 0, offsetY: 4 })
            .offset({ y: this.downloadMode ? 0 : -26 })
            .onClick(() => {
              if (this.deletePath !== '') {
                this.deletePath = ''; // cancel delete
              } else if (this.downloadMode) {
                this.downloadMode = false;
              } else {
                this.showSettings = false;
                resumeDoom();
              }
            })

            // Blue (enter Download) only in the slot view, outside delete mode.
            // In Download mode only ✕ (back) remains.
            if (!this.downloadMode && this.deletePath === '') {
              // Download - center, lowest: switches to the download list.
              Button({ type: ButtonType.Circle }) {
                Column({ space: 2 }) {
                  Text('↓').fontSize(20).fontWeight(FontWeight.Bold).fontColor('#F2FFFFFF')
                  Divider().width(18).strokeWidth(2).color('#F2FFFFFF')
                }
                .justifyContent(FlexAlign.Center)
                .alignItems(HorizontalAlign.Center)
              }
              .width(54)
              .height(54)
              .borderRadius(27)
              .linearGradient({
                direction: GradientDirection.Bottom,
                colors: [['#3AA6CE', 0.0], ['#15597F', 1.0]]
              })
              .opacity(0.82)
              .border({ width: 1, color: '#33FFFFFF' })
              .shadow({ color: '#59000000', radius: 12, offsetX: 0, offsetY: 4 })
              .onClick(() => {
                this.downloadMode = true;
              })
            }

            // Green ✓ - in the slot view: Apply; in delete mode: confirm the
            // deletion. Hidden in Download mode.
            if (!this.downloadMode) {
              Button({ type: ButtonType.Circle }) {
                Text('✓')
                  .fontSize(22)
                  .fontWeight(FontWeight.Bold)
                  .fontColor('#F2FFFFFF')
              }
              .width(54)
              .height(54)
              .borderRadius(27)
              .linearGradient({
                direction: GradientDirection.Bottom,
                colors: [['#5AC15E', 0.0], ['#2E7D33', 1.0]] // always green (OK/confirm)
              })
              .opacity(0.82)
              .border({ width: 1, color: '#33FFFFFF' })
              .shadow({ color: '#59000000', radius: 12, offsetX: 0, offsetY: 4 })
              .offset({ y: -26 })
              .onClick(() => {
                if (this.deletePath !== '') {
                  this.confirmDelete();
                } else {
                  this.applyAndRestart();
                }
              })
            }
          }
          .alignItems(VerticalAlign.Center)
          .justifyContent(FlexAlign.Center)
          .margin({ bottom: 14 })
        }
        .width('100%')
        .height('100%')
        .backgroundColor('#F2101010')
      }

      // Crown: turn left/right (requires focus on the component).
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
