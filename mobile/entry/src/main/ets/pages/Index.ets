import { common, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { picker, fileIo as fs } from '@kit.CoreFileKit';
import {
  DOOM_XCOMPONENT_LIBRARY,
  DoomAction,
  getDoomVersion,
  mapHardwareKey,
  pauseDoom,
  pushDoomKey,
  pushDoomRawKey,
  resumeDoom,
  startDoom
} from 'doom';

/** One IWAD entry shown in the settings list. */
interface WadEntry {
  name: string;
  path: string; // '' = built-in Freedoom
}

/** Persisted user settings. */
interface Settings {
  iwad?: string;
}

// Analog joysticks (a phone has more room than a watch).
const JOY_SIZE = 130;      // ring diameter
const KNOB_SIZE = 54;      // knob diameter
const JOY_MAX = (JOY_SIZE - KNOB_SIZE) / 2; // max deflection
const JOY_TH = 18;         // axis dead zone
const FIRE_SIZE = 92;      // round fire button

/** Main game screen: dual-stick controls, FIRE, weapon switch, USE overlay, settings. */
@Entry
@Component
struct Index {
  @State status: string = 'starting…';
  @State showSettings: boolean = false;
  @State wads: WadEntry[] = [];
  @State selectedPath: string = '';
  @State overlayOpacity: number = 1;
  @State lKnobX: number = 0;
  @State lKnobY: number = 0;
  @State rKnobX: number = 0;
  private idleTimer: number = -1;
  private useDownX = 0;
  private useDownY = 0;
  private useDownT = 0;
  // Axis states for the left joystick (movement) and right (turn) — a key is emitted on change.
  private lUp = false;
  private lDown = false;
  private lStrafeL = false;
  private lStrafeR = false;
  private rTurnL = false;
  private rTurnR = false;
  // Multi-touch: id of the finger assigned to each joystick (-1 = none).
  // Without this, both handlers would read touches[0] and confuse fingers.
  private lFingerId = -1;
  private rFingerId = -1;

  /** Sends a short down/up tap for the given action (menu presses). */
  private tapKey(action: DoomAction): void {
    pushDoomKey(action, true);
    setTimeout(() => {
      pushDoomKey(action, false);
    }, 60);
  }

  /** Emits a key edge only when the pressed-state changes; returns the new state. */
  private setJoyKey(action: DoomAction, pressed: boolean, current: boolean): boolean {
    if (pressed !== current) {
      pushDoomKey(action, pressed);
    }
    return pressed;
  }

  /** Maps a touch point to the left knob offset and the movement/strafe keys. */
  private updateLeftAxes(x: number, y: number): void {
    let dx = x - JOY_SIZE / 2;
    let dy = y - JOY_SIZE / 2;
    const len = Math.sqrt(dx * dx + dy * dy);
    if (len > JOY_MAX) {
      dx = dx * JOY_MAX / len;
      dy = dy * JOY_MAX / len;
    }
    this.lKnobX = dx;
    this.lKnobY = dy;
    this.lUp = this.setJoyKey(DoomAction.Up, dy < -JOY_TH, this.lUp);
    this.lDown = this.setJoyKey(DoomAction.Down, dy > JOY_TH, this.lDown);
    this.lStrafeL = this.setJoyKey(DoomAction.StrafeLeft, dx < -JOY_TH, this.lStrafeL);
    this.lStrafeR = this.setJoyKey(DoomAction.StrafeRight, dx > JOY_TH, this.lStrafeR);
  }

  /** Recenters the left knob and releases its movement/strafe keys. */
  private resetLeftAxes(): void {
    this.lKnobX = 0;
    this.lKnobY = 0;
    this.lUp = this.setJoyKey(DoomAction.Up, false, this.lUp);
    this.lDown = this.setJoyKey(DoomAction.Down, false, this.lDown);
    this.lStrafeL = this.setJoyKey(DoomAction.StrafeLeft, false, this.lStrafeL);
    this.lStrafeR = this.setJoyKey(DoomAction.StrafeRight, false, this.lStrafeR);
  }

  /** Maps a horizontal touch to the right knob offset and the turn keys. */
  private updateRightAxis(x: number): void {
    let dx = x - JOY_SIZE / 2;
    if (dx > JOY_MAX) { dx = JOY_MAX; }
    if (dx < -JOY_MAX) { dx = -JOY_MAX; }
    this.rKnobX = dx;
    this.rTurnL = this.setJoyKey(DoomAction.Left, dx < -JOY_TH, this.rTurnL);
    this.rTurnR = this.setJoyKey(DoomAction.Right, dx > JOY_TH, this.rTurnR);
  }

  /** Recenters the right knob and releases its turn keys. */
  private resetRightAxis(): void {
    this.rKnobX = 0;
    this.rTurnL = this.setJoyKey(DoomAction.Left, false, this.rTurnL);
    this.rTurnR = this.setJoyKey(DoomAction.Right, false, this.rTurnR);
  }

  /**
   * Left joystick (Y axis = forward/back, X = strafe). Tracks its own finger by
   * id so a second finger on the right joystick can't steal it.
   */
  private handleLeftJoystick(event: TouchEvent): void {
    if (event.type === TouchType.Down) {
      const c = event.changedTouches[0];
      if (c === undefined) {
        return;
      }
      this.lFingerId = c.id;
      this.updateLeftAxes(c.x, c.y);
      return;
    }
    // Releasing OUR finger (present in changedTouches on Up/Cancel) = reset to
    // center — even when touches still contains the finger being lifted.
    if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      const released = event.changedTouches.find((tt: TouchObject) => tt.id === this.lFingerId);
      if (released !== undefined) {
        this.lFingerId = -1;
        this.resetLeftAxes();
        return;
      }
    }
    const t = event.touches.find((tt: TouchObject) => tt.id === this.lFingerId);
    if (t !== undefined) {
      this.updateLeftAxes(t.x, t.y);
    }
  }

  /** Right joystick (X axis only = turn). Tracks its own finger by id. */
  private handleRightJoystick(event: TouchEvent): void {
    if (event.type === TouchType.Down) {
      const c = event.changedTouches[0];
      if (c === undefined) {
        return;
      }
      this.rFingerId = c.id;
      this.updateRightAxis(c.x);
      return;
    }
    if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      const released = event.changedTouches.find((tt: TouchObject) => tt.id === this.rFingerId);
      if (released !== undefined) {
        this.rFingerId = -1;
        this.resetRightAxis();
        return;
      }
    }
    const t = event.touches.find((tt: TouchObject) => tt.id === this.rFingerId);
    if (t !== undefined) {
      this.updateRightAxis(t.x);
    }
  }

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

  private getWadsDir(): string {
    return this.getCtx().filesDir + '/wads';
  }

  private initialized = false;

  // getHostContext() is unavailable before the UI is built (aboutToAppear
  // crashes with "context is invalid") — lazy init from onLoad/⚙ instead.
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
      this.selectedPath = ''; // missing/corrupt settings file = built-in Freedoom
    }
    this.refreshWads();
  }

  private getSettingsPath(): string {
    return this.getCtx().filesDir + '/settings.json';
  }

  /** Persists the selected IWAD path to settings.json. */
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

  /** Resume the engine when the page becomes visible. */
  onPageShow(): void {
    resumeDoom();
  }

  /** Pause the engine when the page is hidden. */
  onPageHide(): void {
    pauseDoom();
  }

  /** Rescans the wads directory and rebuilds the IWAD list. */
  private refreshWads(): void {
    try {
      fs.mkdirSync(this.getWadsDir());
    } catch (err) {
      // directory already exists — OK
    }
    let files: string[] = [];
    try {
      files = fs.listFileSync(this.getWadsDir())
        .filter((f: string) => f.toLowerCase().endsWith('.wad'))
        .sort();
    } catch (err) {
      hilog.error(0x0000, 'Doom4OH', 'refreshWads: listFile failed: %{public}s', JSON.stringify(err));
    }
    const entries: WadEntry[] = [{ name: 'Freedoom (built-in)', path: '' }];
    for (const f of files) {
      entries.push({ name: f, path: `${this.getWadsDir()}/${f}` });
    }
    this.wads = entries;
    // A selection pointing at a deleted file falls back to Freedoom.
    if (this.selectedPath !== '' && !entries.some((e: WadEntry) => e.path === this.selectedPath)) {
      this.selectedPath = '';
    }
  }

  /** Opens the document picker and copies the chosen WAD into the wads directory. */
  private async importWad(): Promise<void> {
    try {
      const dvp = new picker.DocumentViewPicker(this.getCtx());
      const uris = await dvp.select({ maxSelectNumber: 1, fileSuffixFilters: ['WAD|.wad'] });
      if (!uris || uris.length === 0) {
        return;
      }
      const uri = uris[0];
      const name = decodeURIComponent(uri.split('/').pop() ?? 'import.wad');
      const src = fs.openSync(uri, fs.OpenMode.READ_ONLY);
      fs.copyFileSync(src.fd, `${this.getWadsDir()}/${name}`);
      fs.closeSync(src);
      this.refreshWads();
      this.status = `imported ${name}`;
    } catch (err) {
      this.status = `import failed: ${JSON.stringify(err)}`;
    }
  }

  /** Saves settings and restarts the app to load the newly selected IWAD. */
  private applyAndRestart(): void {
    this.saveSettings();
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

  /** Glass-style momentary key button that presses/releases an action on touch. */
  @Builder
  keyButton(label: string, action: DoomAction, buttonWidth: number) {
    Text(label)
      .width(buttonWidth)
      .height(52)
      .fontSize(17)
      .fontColor('#73FFFFFF')
      .textAlign(TextAlign.Center)
      // glass: transparent gradient with a lighter top (gloss) + border + shadow
      .linearGradient({
        angle: 180,
        colors: [['#26FFFFFF', 0], ['#0DFFFFFF', 0.45], ['#05FFFFFF', 1]]
      })
      .borderRadius(12)
      .border({ width: 1, color: '#1FFFFFFF' })
      .shadow({ radius: 10, color: '#59000000', offsetX: 0, offsetY: 4 })
      .onTouch((event: TouchEvent) => {
        if (event.type === TouchType.Down) {
          pushDoomKey(action, true);
        } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
          pushDoomKey(action, false);
        }
      })
  }

  /** Icon key matching the ⚙ button width (52) — used for ESC. */
  @Builder
  iconKey(icon: string, action: DoomAction) {
    Text(icon)
      .width(52)
      .height(52)
      .fontSize(24)
      .fontColor('#73FFFFFF')
      .textAlign(TextAlign.Center)
      .linearGradient({
        angle: 180,
        colors: [['#26FFFFFF', 0], ['#0DFFFFFF', 0.45], ['#05FFFFFF', 1]]
      })
      .borderRadius(12)
      .border({ width: 1, color: '#1FFFFFFF' })
      .shadow({ radius: 10, color: '#59000000', offsetX: 0, offsetY: 4 })
      .onTouch((event: TouchEvent) => {
        if (event.type === TouchType.Down) {
          pushDoomKey(action, true);
        } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
          pushDoomKey(action, false);
        }
      })
  }

  /**
   * Glass knob (radial gradient + gloss). Used inline with a direct reference to
   * the @State offset — a @Builder parameter would not be reactive to state changes.
   */
  @Builder
  knobVisual() {
    Column()
      .width(KNOB_SIZE)
      .height(KNOB_SIZE)
      .borderRadius(KNOB_SIZE / 2)
      .radialGradient({
        center: ['50%', '38%'],
        radius: KNOB_SIZE / 2,
        colors: [['#73FFFFFF', 0], ['#40FFFFFF', 0.6], ['#1FFFFFFF', 1]]
      })
      .border({ width: 1, color: '#40FFFFFF' })
      .shadow({ radius: 6, color: '#59000000', offsetX: 0, offsetY: 2 })
      .hitTestBehavior(HitTestMode.None)
  }

  /**
   * Triangular weapon switch (wearable style: outline + transparent fill).
   * pointRight=true → arrow pointing right (next weapon).
   */
  @Builder
  weaponTriangle(pointRight: boolean, action: DoomAction) {
    Polygon({ width: 44, height: 44 })
      .points(pointRight ? [[8, 6], [8, 38], [38, 22]] : [[38, 6], [38, 38], [8, 22]])
      .fill('#12FFFFFF')
      .stroke('#33FFFFFF')
      .strokeWidth(1.5)
      .onClick(() => {
        this.tapKey(action);
      })
  }

  /** Round hold button (fire / weapon) with a down/up action. */
  @Builder
  roundKey(label: string, action: DoomAction, size: number, fontSize: number) {
    Text(label)
      .width(size)
      .height(size)
      .fontSize(fontSize)
      .fontColor('#8CFFFFFF')
      .textAlign(TextAlign.Center)
      .borderRadius(size / 2)
      .linearGradient({
        angle: 180,
        colors: [['#30FFFFFF', 0], ['#10FFFFFF', 0.5], ['#08FFFFFF', 1]]
      })
      .border({ width: 1, color: '#26FFFFFF' })
      .shadow({ radius: 10, color: '#59000000', offsetX: 0, offsetY: 4 })
      .onTouch((event: TouchEvent) => {
        if (event.type === TouchType.Down) {
          pushDoomKey(action, true);
        } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
          pushDoomKey(action, false);
        }
      })
  }

  /** Text button with a tap handler, used in the settings panel. */
  @Builder
  actionButton(label: string, onClick: () => void) {
    Text(label)
      .padding({ left: 16, right: 16, top: 10, bottom: 10 })
      .fontSize(15)
      .fontColor('#73FFFFFF')
      .linearGradient({
        angle: 180,
        colors: [['#4DFFFFFF', 0], ['#1FFFFFFF', 0.5], ['#12FFFFFF', 1]]
      })
      .borderRadius(10)
      .border({ width: 1, color: '#1FFFFFFF' })
      .shadow({ radius: 8, color: '#4D000000', offsetX: 0, offsetY: 3 })
      .onClick(onClick)
  }

  /** Builds the game surface, control overlay, and settings panel. */
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
          const ok = startDoom(this.getCtx().resourceManager, this.getCtx().filesDir, this.selectedPath);
          this.status = ok ? `native ${getDoomVersion()}` : 'START FAILED';
          this.armIdleTimer();
        })
      // XComponent SURFACE doesn't receive onTouch on real HW — a separate
      // transparent layer above the game catches the USE tap (below the controls,
      // which pass touch from their empty areas down here via HitTestMode.Transparent).
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#01000000') // almost transparent — needed to catch touch
        .onTouch((event: TouchEvent) => {
          if (event.type === TouchType.Down) {
            const t = event.touches[0];
            if (t !== undefined) {
              this.useDownX = t.x;
              this.useDownY = t.y;
              this.useDownT = Date.now();
            }
          } else if (event.type === TouchType.Up) {
            const t = event.changedTouches[0];
            if (t !== undefined) {
              const dt = Date.now() - this.useDownT;
              const dx = Math.abs(t.x - this.useDownX);
              const dy = Math.abs(t.y - this.useDownY);
              if (dt < 300 && dx < 30 && dy < 30) {
                this.tapKey(DoomAction.Use);
              }
            }
          }
        })

      Column() {
        Row({ space: 10 }) {
          Text('⚙')
            .width(52)
            .height(52)
            .fontSize(26)
            .fontColor('#73FFFFFF')
            .textAlign(TextAlign.Center)
            .linearGradient({
              angle: 180,
              colors: [['#26FFFFFF', 0], ['#0DFFFFFF', 0.45], ['#05FFFFFF', 1]]
            })
            .borderRadius(12)
            .border({ width: 1, color: '#1FFFFFFF' })
            .shadow({ radius: 10, color: '#59000000', offsetX: 0, offsetY: 4 })
            .onClick(() => {
              this.ensureInit();
              this.refreshWads();
              this.showSettings = true;
              pauseDoom();
            })
          this.iconKey('≡', DoomAction.Escape)
        }
        .width('100%')

        Blank()

        Row() {
          // LEFT thumb: analog joystick (Y axis = forward/back, X axis = strafe).
          Stack() {
            Circle()
              .width(JOY_SIZE)
              .height(JOY_SIZE)
              .fill('#14FFFFFF')
              .stroke('#33FFFFFF')
              .strokeWidth(1.5)
            Stack() {
              this.knobVisual()
              Ellipse()
                .width(KNOB_SIZE * 0.4)
                .height(KNOB_SIZE * 0.22)
                .fill('#66FFFFFF')
                .offset({ y: -KNOB_SIZE * 0.16 })
                .hitTestBehavior(HitTestMode.None)
            }
            .width(KNOB_SIZE)
            .height(KNOB_SIZE)
            .offset({ x: this.lKnobX, y: this.lKnobY })
            .hitTestBehavior(HitTestMode.None)
          }
          .width(JOY_SIZE)
          .height(JOY_SIZE)
          .onTouch((event: TouchEvent) => {
            this.handleLeftJoystick(event);
          })

          Blank()

          // RIGHT thumb: [◀ ▶] weapon change ABOVE the retro FIRE button, turn
          // joystick below it. All centered on one vertical axis.
          Column({ space: 10 }) {
            Row({ space: 22 }) {
              this.weaponTriangle(false, DoomAction.PrevWeapon)
              this.weaponTriangle(true, DoomAction.NextWeapon)
            }
            .alignItems(VerticalAlign.Center)

            // FIRE: white ring + semi-transparent red "ball top" sphere (arcade)
            // — bright gloss on top, darker edge, translucent.
            Stack() {
              Circle()
                .width(FIRE_SIZE)
                .height(FIRE_SIZE)
                .fill('#14FFFFFF')
                .stroke('#40FFFFFF')
                .strokeWidth(2)
              // glass sphere: radial gradient, lighter in the upper half
              Column()
                .width(FIRE_SIZE * 2 / 3)
                .height(FIRE_SIZE * 2 / 3)
                .borderRadius(FIRE_SIZE / 3)
                .radialGradient({
                  center: ['50%', '38%'],
                  radius: FIRE_SIZE / 3,
                  colors: [['#B3FF8A7A', 0], ['#99E5382B', 0.55], ['#B3800E06', 1]]
                })
                .border({ width: 1.5, color: '#59FFB0A6' })
                .shadow({ radius: 8, color: '#73000000', offsetX: 0, offsetY: 3 })
              // gloss: bright highlight at the top of the sphere
              Ellipse()
                .width(FIRE_SIZE * 0.32)
                .height(FIRE_SIZE * 0.18)
                .fill('#73FFFFFF')
                .offset({ y: -FIRE_SIZE * 0.14 })
            }
            .width(FIRE_SIZE)
            .height(FIRE_SIZE)
            .onTouch((event: TouchEvent) => {
              if (event.type === TouchType.Down) {
                pushDoomKey(DoomAction.Fire, true);
                this.tapKey(DoomAction.Enter); // confirm in menus/prompts
              } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                pushDoomKey(DoomAction.Fire, false);
              }
              // USE (doors) = tap in the center of the screen — no fire.
            })

            // Horizontal turn joystick: the knob moves only horizontally.
            Stack() {
              Circle()
                .width(JOY_SIZE)
                .height(JOY_SIZE)
                .fill('#14FFFFFF')
                .stroke('#33FFFFFF')
                .strokeWidth(1.5)
              Stack() {
                this.knobVisual()
                Ellipse()
                  .width(KNOB_SIZE * 0.4)
                  .height(KNOB_SIZE * 0.22)
                  .fill('#66FFFFFF')
                  .offset({ y: -KNOB_SIZE * 0.16 })
                  .hitTestBehavior(HitTestMode.None)
              }
              .width(KNOB_SIZE)
              .height(KNOB_SIZE)
              .offset({ x: this.rKnobX, y: 0 })
              .hitTestBehavior(HitTestMode.None)
            }
            .width(JOY_SIZE)
            .height(JOY_SIZE)
            .onTouch((event: TouchEvent) => {
              this.handleRightJoystick(event);
            })
          }
          .alignItems(HorizontalAlign.Center) // shared vertical axis: arrows/FIRE/joystick
        }
        .width('100%')
        .alignItems(VerticalAlign.Bottom)

        Text(`Doom4OH ${this.status}`)
          .fontSize(10)
          .fontColor('#66FFFFFF')
          .width('100%')
          .textAlign(TextAlign.Center)
          .margin({ top: 4 })
      }
      .height('100%')
      .width('100%')
      .padding(14)
      .opacity(this.overlayOpacity)
      .enabled(this.overlayOpacity > 0.1) // hidden buttons don't catch touch
      // Empty overlay areas pass touch down to the USE layer beneath; buttons and
      // joysticks (own onTouch/onClick) still catch it. Transparent (not None) —
      // None doesn't propagate to siblings below in a Stack.
      .hitTestBehavior(HitTestMode.Transparent)

      if (this.showSettings) {
        Column({ space: 14 }) {
          Row() {
            Blank().width(36)
            Text('Select IWAD')
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor(Color.White)
              .layoutWeight(1)
              .textAlign(TextAlign.Center)
            Text('✕')
              .width(36)
              .height(36)
              .fontSize(18)
              .fontColor('#B3FFFFFF')
              .textAlign(TextAlign.Center)
              .borderRadius(18)
              .backgroundColor('#22FFFFFF')
              .onClick(() => {
                this.showSettings = false;
                resumeDoom();
              })
          }
          .width('100%')

          List({ space: 4 }) {
            ForEach(this.wads, (w: WadEntry) => {
              ListItem() {
                Row() {
                  Text(w.name)
                    .fontSize(15)
                    .fontColor(this.selectedPath === w.path ? '#FFC93C' : Color.White)
                  Blank()
                  if (this.selectedPath === w.path) {
                    Text('✓').fontSize(15).fontColor('#FFC93C')
                  }
                }
                .width('100%')
                .padding({ left: 12, right: 12, top: 8, bottom: 8 })
                .borderRadius(8)
                .backgroundColor(this.selectedPath === w.path ? '#33FFC93C' : '#22FFFFFF')
                .onClick(() => {
                  this.selectedPath = w.path;
                })
              }
            }, (w: WadEntry) => w.path + w.name)
          }
          .width('100%')
          .height(170)

          Row({ space: 12 }) {
            this.actionButton('Load WAD…', () => {
              this.importWad();
            })
            this.actionButton('Apply & Restart', () => {
              this.applyAndRestart();
            })
          }
        }
        .width(560)
        .padding(20)
        .backgroundColor('#E6202020')
        .borderRadius(16)
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
