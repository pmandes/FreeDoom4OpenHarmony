import { DoomAction, pushDoomKey } from 'doom';

// Analog joysticks (a phone has more room than a watch).
const JOY_SIZE = 130;      // ring diameter
const KNOB_SIZE = 54;      // knob diameter
const JOY_MAX = (JOY_SIZE - KNOB_SIZE) / 2; // max deflection
const JOY_TH = 18;         // axis dead zone
const FIRE_SIZE = 92;      // round fire button

/**
 * The in-game touch overlay: dual analog sticks, FIRE, weapon switch, the USE
 * tap layer, and the settings / menu buttons. Owns its own input state (knob
 * offsets, per-finger tracking) and drives the engine directly via pushDoomKey.
 * The page passes the overlay opacity and a callback to open settings; everything
 * else is self-contained.
 */
@Component
export struct GameControls {
  @Prop controlsOpacity: number;
  onOpenSettings: () => void = () => {};

  @State private lKnobX: number = 0;
  @State private lKnobY: number = 0;
  @State private rKnobX: number = 0;
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
  // FIRE is a held key (not a tap), so track it to release it on demand.
  private firing = false;

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
   * Releases every held control (both stick axes and FIRE) and drops finger tracking.
   * Called before opening settings: the sheet disables this overlay, so a finger held
   * on a stick or FIRE would never deliver its Up here and the native pause keeps the
   * key state, leaving movement/firing stuck on when the game resumes.
   */
  releaseAllControls(): void {
    this.lFingerId = -1;
    this.rFingerId = -1;
    this.resetLeftAxes();
    this.resetRightAxis();
    if (this.firing) {
      pushDoomKey(DoomAction.Fire, false);
      this.firing = false;
    }
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

  build() {
    Stack() {
      // XComponent SURFACE doesn't receive onTouch on real HW — a transparent
      // layer above the game catches the USE tap (below the controls, which pass
      // touch from their empty areas down here via HitTestMode.Transparent).
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
              // Neutralise any held stick/FIRE before the sheet disables this overlay,
              // so its Up isn't lost and the game doesn't resume with input stuck on.
              this.releaseAllControls();
              this.onOpenSettings();
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
                this.firing = true;
                this.tapKey(DoomAction.Enter); // confirm in menus/prompts
              } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                pushDoomKey(DoomAction.Fire, false);
                this.firing = false;
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
      }
      .height('100%')
      .width('100%')
      .padding(14)
      .opacity(this.controlsOpacity)
      .enabled(this.controlsOpacity > 0.1) // hidden buttons don't catch touch
      // Empty overlay areas pass touch down to the USE layer beneath; buttons and
      // joysticks (own onTouch/onClick) still catch it. Transparent (not None) —
      // None doesn't propagate to siblings below in a Stack.
      .hitTestBehavior(HitTestMode.Transparent)
    }
    .width('100%')
    .height('100%')
  }
}
