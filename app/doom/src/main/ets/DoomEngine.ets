import native from 'libdoom.so';
import { KeyCode } from '@kit.InputKit';
import type { resourceManager } from '@kit.LocalizationKit';

/**
 * Native library name for the XComponent that hosts the game:
 * XComponent({ ..., libraryname: DOOM_XCOMPONENT_LIBRARY })
 */
export const DOOM_XCOMPONENT_LIBRARY = 'doom';

/** Input actions — values must match the input::Action enum in native code. */
export enum DoomAction {
  Up = 0,
  Down = 1,
  Left = 2,
  Right = 3,
  Fire = 4,
  Use = 5,
  Enter = 6,
  Escape = 7,
  StrafeLeft = 8,
  StrafeRight = 9,
  PrevWeapon = 10,
  NextWeapon = 11,
  Run = 12,
}

/** Version of the native library. */
export function getDoomVersion(): string {
  return native.getVersion();
}

/**
 * Starts the game loop on the native thread. Call after the XComponent surface
 * has been created (onLoad). iwadPath: absolute path to the selected IWAD; empty
 * or omitted -> the built-in Freedoom copied from rawfile into the sandbox.
 */
export function startDoom(resMgr: resourceManager.ResourceManager, filesDir: string, iwadPath: string = ''): boolean {
  return native.startGame(resMgr, filesDir, iwadPath);
}

/** Key event from the overlay (down/up). */
export function pushDoomKey(action: DoomAction, pressed: boolean): void {
  native.pushKey(action, pressed);
}

/** Backspace code for pushDoomChar. */
export const DOOM_CHAR_BACKSPACE = 0x7f;

/** Enter code for pushDoomChar. */
export const DOOM_CHAR_ENTER = 13;

/**
 * Raw ASCII character for typing text in the engine (e.g. save names).
 * Sends down+up for a single code.
 */
export function pushDoomChar(code: number): void {
  native.pushChar(code);
}

// ── Physical keyboard (USB/emulator) ───────────────────────────────────────

// doomkeys.h codes for special keys.
const DK_UP = 0xad;
const DK_DOWN = 0xaf;
const DK_LEFT = 0xac;
const DK_RIGHT = 0xae;
const DK_FIRE = 0xa3;
const DK_USE = 0xa2;
const DK_RSHIFT = 0xb6;
const DK_LALT = 0xb8;
const DK_F1 = 0xbb; // F1..F10 in sequence; F11=0xd7, F12=0xd8

let hardwareMap: Map<number, number> | null = null;

/** Builds (and lazily caches) the KeyCode -> doomkeys lookup map. */
function hardwareKeyMap(): Map<number, number> {
  if (hardwareMap !== null) {
    return hardwareMap;
  }
  const m = new Map<number, number>();
  m.set(KeyCode.KEYCODE_DPAD_UP, DK_UP);
  m.set(KeyCode.KEYCODE_DPAD_DOWN, DK_DOWN);
  m.set(KeyCode.KEYCODE_DPAD_LEFT, DK_LEFT);
  m.set(KeyCode.KEYCODE_DPAD_RIGHT, DK_RIGHT);
  m.set(KeyCode.KEYCODE_CTRL_LEFT, DK_FIRE);
  m.set(KeyCode.KEYCODE_CTRL_RIGHT, DK_FIRE);
  m.set(KeyCode.KEYCODE_SPACE, DK_USE);
  m.set(KeyCode.KEYCODE_SHIFT_LEFT, DK_RSHIFT);
  m.set(KeyCode.KEYCODE_SHIFT_RIGHT, DK_RSHIFT);
  m.set(KeyCode.KEYCODE_ALT_LEFT, DK_LALT);
  m.set(KeyCode.KEYCODE_ALT_RIGHT, DK_LALT);
  m.set(KeyCode.KEYCODE_ENTER, DOOM_CHAR_ENTER);
  m.set(KeyCode.KEYCODE_ESCAPE, 27);
  m.set(KeyCode.KEYCODE_TAB, 9);
  m.set(KeyCode.KEYCODE_DEL, DOOM_CHAR_BACKSPACE);
  m.set(KeyCode.KEYCODE_MINUS, 0x2d);
  m.set(KeyCode.KEYCODE_EQUALS, 0x3d);
  m.set(KeyCode.KEYCODE_LEFT_BRACKET, 91);  // previous weapon (port binding)
  m.set(KeyCode.KEYCODE_RIGHT_BRACKET, 93); // next weapon
  m.set(KeyCode.KEYCODE_COMMA, 44);
  m.set(KeyCode.KEYCODE_PERIOD, 46);
  m.set(KeyCode.KEYCODE_SLASH, 47);
  m.set(KeyCode.KEYCODE_SEMICOLON, 59);
  m.set(KeyCode.KEYCODE_APOSTROPHE, 39);
  m.set(KeyCode.KEYCODE_GRAVE, 96);
  const aBase: number = KeyCode.KEYCODE_A;
  for (let i = 0; i < 26; i++) {
    m.set(aBase + i, 97 + i); // a..z (cheats, y/n prompts)
  }
  const zeroBase: number = KeyCode.KEYCODE_0;
  for (let i = 0; i < 10; i++) {
    m.set(zeroBase + i, 48 + i); // 0..9 (weapon selection)
  }
  const f1Base: number = KeyCode.KEYCODE_F1;
  for (let i = 0; i < 10; i++) {
    m.set(f1Base + i, DK_F1 + i); // F1..F10
  }
  m.set(f1Base + 10, 0xd7); // F11
  m.set(f1Base + 11, 0xd8); // F12
  hardwareMap = m;
  return m;
}

/** Maps a physical keyboard KeyCode to a doomkeys code; 0 = unsupported. */
export function mapHardwareKey(keyCode: number): number {
  return hardwareKeyMap().get(keyCode) ?? 0;
}

/** Physical keyboard key (down/up separately — keys may be held). */
export function pushDoomRawKey(code: number, pressed: boolean): void {
  native.pushRawKey(code, pressed);
}

/** Pauses the tick loop (background). Game state remains in memory. */
export function pauseDoom(): void {
  native.pauseGame();
}

/** Resumes the tick loop after a pause. */
export function resumeDoom(): void {
  native.resumeGame();
}

/**
 * True once the engine tried to exit (Quit Game menu or a fatal error). The page
 * polls this and calls terminateSelf, because a native exit() is aborted by appspawn.
 */
export function isDoomQuitRequested(): boolean {
  return native.isQuitRequested();
}
