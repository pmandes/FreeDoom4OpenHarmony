import type { resourceManager } from '@kit.LocalizationKit';
import { isDoomQuitRequested, pauseDoom, resumeDoom, startDoom } from 'doom';

/** Invoked when the engine has asked to quit (Quit Game menu or a fatal error). */
export type QuitHandler = () => void;

/**
 * Owns the native engine lifecycle: start, pause/resume, and the quit watcher.
 * Plain class (no ArkUI) so it stays testable; the view calls it and reacts to
 * the QuitHandler. Side effects (native calls, timers) live here, not in the view.
 */
export class GameViewModel {
  private quitTimer: number = -1;
  private started: boolean = false;

  /** True once the engine started successfully. */
  isStarted(): boolean {
    return this.started;
  }

  /**
   * Starts the game loop on the native thread. Call after the XComponent surface
   * exists. iwadPath: absolute path of the chosen IWAD ('' = built-in Freedoom).
   */
  start(resMgr: resourceManager.ResourceManager, filesDir: string, iwadPath: string): boolean {
    this.started = startDoom(resMgr, filesDir, iwadPath);
    return this.started;
  }

  /** Pauses the tick loop (page hidden / app background). State is kept. */
  pause(): void {
    pauseDoom();
  }

  /** Resumes the tick loop (page shown / app foreground). */
  resume(): void {
    resumeDoom();
  }

  /**
   * Polls the native quit flag; when the engine asked to exit, invokes onQuit
   * once and stops. A native exit() would be aborted by appspawn (SIGABRT), so
   * the engine redirects its exit() to a flag the UI watches here.
   */
  armQuitWatcher(onQuit: QuitHandler): void {
    if (this.quitTimer >= 0) {
      return;
    }
    this.quitTimer = setInterval(() => {
      if (isDoomQuitRequested()) {
        this.stopQuitWatcher();
        onQuit();
      }
    }, 250);
  }

  /** Stops the quit watcher. */
  stopQuitWatcher(): void {
    if (this.quitTimer >= 0) {
      clearInterval(this.quitTimer);
      this.quitTimer = -1;
    }
  }
}
