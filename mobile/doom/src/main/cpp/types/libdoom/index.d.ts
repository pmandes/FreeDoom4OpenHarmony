import type { resourceManager } from '@kit.LocalizationKit';

/** Returns the native library version string. */
export const getVersion: () => string;

/**
 * Starts the game loop on the native thread. iwadPath: absolute path to the
 * selected IWAD; empty or nonexistent -> the built-in Freedoom copied from rawfile.
 */
export const startGame: (resMgr: resourceManager.ResourceManager, filesDir: string, iwadPath?: string) => boolean;

/**
 * Key event. Actions: 0=up 1=down 2=left 3=right 4=fire 5=use
 * 6=enter 7=escape 8=strafeLeft 9=strafeRight.
 */
export const pushKey: (action: number, pressed: boolean) => void;

/** Raw ASCII character (down+up) for typing text (backspace=0x7f, enter=13). */
export const pushChar: (code: number) => void;

/** Raw doomkeys/ASCII code from a physical keyboard (down/up separately). */
export const pushRawKey: (code: number, pressed: boolean) => void;

/** Pauses the tick loop (background). Game state remains in memory. */
export const pauseGame: () => void;

/** Resumes the tick loop after a pause. */
export const resumeGame: () => void;

/**
 * True once the engine tried to exit (Quit Game menu or a fatal error). The UI polls
 * this and calls terminateSelf, since a native exit() is aborted by appspawn.
 */
export const isQuitRequested: () => boolean;
