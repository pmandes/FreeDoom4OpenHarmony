import { DoomAction, pushDoomKey } from 'doom';

// Analog joystick (bottom center): ring + draggable knob.
const JOY_SIZE = 60;
const KNOB_SIZE = 24;
const JOY_MAX = (JOY_SIZE - KNOB_SIZE) / 2; // max knob travel
const JOY_TH = 9; // axis trigger threshold (dead zone)

/**
 * The watch on-screen controls: the bottom weapon triangles + analog joystick
 * (movement / strafe) and the top gear (settings) + menu buttons. Owns its own
 * joystick input state and drives the engine directly via pushDoomKey. The crown
 * (turning) and the game-surface tap gestures stay on the page, which owns the
 * focused root; this overlay reports only the settings open through a callback.
 */
@Component
export struct WatchControls {
  onOpenSettings: () => void = () => {};

  @State private knobX: number = 0;
  @State private knobY: number = 0;
  private joyUp = false;
  private joyDown = false;
  private joyLeft = false;
  private joyRight = false;

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

  build() {
    Stack() {
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
              this.onOpenSettings();
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
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.None) // empty areas pass touch through to the game surface below
  }
}
