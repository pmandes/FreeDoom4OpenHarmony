import { Settings, WadEntry, SettingsStore, WadRepository, SoundfontRepository } from 'core';

/** Notifies the view that settings state changed (it re-reads the snapshot). */
export type SettingsListener = () => void;

/** Label for the bundled Freedoom, which is not a file in the sandbox. */
const BUILT_IN_WAD_LABEL = 'Freedoom (built-in)';

/** settings.json schema version written by this build (see Settings.version). */
const SETTINGS_VERSION = 1;

/**
 * Presentation state and operations for the settings screen: the IWAD list and
 * draft selection, and the custom soundfont. Plain class with a change listener
 * (Telegram viewmodel style) — the view mirrors the snapshot into @State. Holds
 * the core repositories; the picker and app restart stay in the (thin) view.
 */
export class SettingsViewModel {
  private readonly store: SettingsStore;
  private readonly wadRepo: WadRepository;
  private readonly sfRepo: SoundfontRepository;
  private listener?: SettingsListener;

  private wadList: WadEntry[] = [{ name: BUILT_IN_WAD_LABEL, path: '' }];
  private selectedPath: string = '';
  // Active soundfont choice: '' = bundled General MIDI, non-empty = the custom file.
  // This is the source of truth, persisted to settings.json — NOT file presence, so
  // choosing built-in sticks even while the custom soundfont.sf2 stays on disk.
  private soundfont: string = '';
  // Label for the custom soundfont, kept even while built-in is active.
  private customName: string = '';
  // Baseline the running engine loaded with — a draft differing from it needs a restart.
  private appliedIwad: string = '';
  private appliedSoundfont: string = '';
  // A same-name re-import overwrites the file the engine is running while leaving the
  // choice unchanged, so track that explicitly to still offer a Restart.
  private iwadReplaced: boolean = false;
  private soundfontReplaced: boolean = false;

  constructor(filesDir: string) {
    this.store = new SettingsStore(filesDir);
    this.wadRepo = new WadRepository(filesDir);
    this.sfRepo = new SoundfontRepository(filesDir);
  }

  setListener(listener: SettingsListener): void {
    this.listener = listener;
  }

  private notify(): void {
    if (this.listener !== undefined) {
      this.listener();
    }
  }

  // ── Snapshot (the view mirrors these into @State) ──────────────────────────

  /** The IWAD list: built-in first, then imported WADs. */
  wads(): WadEntry[] {
    return this.wadList;
  }

  /** Absolute path of the active IWAD ('' = built-in). */
  selection(): string {
    return this.selectedPath;
  }

  /** Active soundfont label ('' = bundled General MIDI, non-empty = custom active). */
  soundfontName(): string {
    return this.soundfont;
  }

  /** True when a custom soundfont file is present (available to switch to). */
  customAvailable(): boolean {
    return this.sfRepo.exists();
  }

  /** Display label for the custom soundfont option. */
  customLabel(): string {
    return this.customName !== '' ? this.customName : 'Custom soundfont';
  }

  /** Absolute path of the soundfont the engine should load ('' = built-in). */
  activeSoundfontPath(): string {
    return this.soundfont !== '' && this.sfRepo.exists() ? this.sfRepo.filePath() : '';
  }

  /** Display name of the IWAD at `path` ('' = built-in). */
  wadName(path: string): string {
    if (path === '') {
      return BUILT_IN_WAD_LABEL;
    }
    for (const e of this.wadList) {
      if (e.path === path) {
        return e.name;
      }
    }
    return path;
  }

  /** True when the draft differs from what the running engine loaded (needs restart). */
  hasPendingChanges(): boolean {
    return this.selectedPath !== this.appliedIwad
      || this.soundfont !== this.appliedSoundfont
      || this.iwadReplaced
      || this.soundfontReplaced;
  }

  /** Human summary of the staged, restart-only changes ('' when none). */
  pendingSummary(): string {
    const parts: string[] = [];
    if (this.selectedPath !== this.appliedIwad || this.iwadReplaced) {
      parts.push(this.wadName(this.selectedPath));
    }
    if (this.soundfont !== this.appliedSoundfont || this.soundfontReplaced) {
      parts.push(this.soundfont !== '' ? this.soundfont : 'General MIDI');
    }
    return parts.join(', ');
  }

  // ── Operations ─────────────────────────────────────────────────────────────

  /** Loads persisted settings and scans the sandbox. Call once it is available. */
  load(): void {
    const s = this.store.load();
    this.selectedPath = s.iwad ?? '';
    const hasFile = this.sfRepo.exists();
    // A legacy file (no version) that stored soundfont: '' predates explicit
    // selection, where a side-loaded soundfont.sf2 was auto-detected — keep that so
    // upgrading users don't silently drop their custom soundfont.
    const legacy = s.version === undefined;
    if (s.soundfont === undefined || (legacy && s.soundfont === '' && hasFile)) {
      // Never chosen, or legacy auto-detect: use the side-loaded file if present.
      this.soundfont = hasFile ? 'Custom soundfont' : '';
    } else {
      // Explicit choice: honour it; a custom file that vanished falls back.
      this.soundfont = s.soundfont;
      if (this.soundfont !== '' && !hasFile) {
        this.soundfont = '';
      }
    }
    // Custom label, kept even while built-in is active: prefer the saved name, then
    // the active soundfont name, else a generic label.
    if (!hasFile) {
      this.customName = '';
    } else if (s.customSoundfont !== undefined && s.customSoundfont !== '') {
      this.customName = s.customSoundfont;
    } else if (this.soundfont !== '') {
      this.customName = this.soundfont;
    } else {
      this.customName = 'Custom soundfont';
    }
    this.rebuildWads();
    // Record the baseline the engine is about to start with.
    this.appliedIwad = this.selectedPath;
    this.appliedSoundfont = this.soundfont;
    this.iwadReplaced = false;
    this.soundfontReplaced = false;
    this.notify();
  }

  /** Rescans imported WADs (e.g. when the settings screen opens) without reloading. */
  rescan(): void {
    this.rebuildWads();
    this.notify();
  }

  private rebuildWads(): void {
    const entries: WadEntry[] = [{ name: BUILT_IN_WAD_LABEL, path: '' }];
    for (const e of this.wadRepo.list()) {
      entries.push(e);
    }
    this.wadList = entries;
    // A selection pointing at a deleted file falls back to the built-in.
    if (this.selectedPath !== '' && !entries.some((e: WadEntry) => e.path === this.selectedPath)) {
      this.selectedPath = '';
    }
  }

  /** Chooses the active IWAD (draft — persisted on apply). */
  selectWad(path: string): void {
    // Ignore a stale selection of a WAD no longer in the list — e.g. a trash-icon
    // click that bubbled to the row handler right after the file was deleted. This
    // keeps selectedPath from pointing at a missing file.
    if (path !== '' && !this.wadList.some((e: WadEntry) => e.path === path)) {
      return;
    }
    this.selectedPath = path;
    this.notify();
  }

  /** Imports a picked WAD (by picker uri); resolves to its file name. */
  async importWad(uri: string): Promise<string> {
    const name = await this.wadRepo.importFrom(uri);
    // Re-importing the WAD the engine is currently running (same name) changes its
    // content without changing the selection — still needs a restart.
    if (`${this.wadRepo.wadsDir()}/${name}` === this.appliedIwad) {
      this.iwadReplaced = true;
    }
    this.rebuildWads();
    this.notify();
    return name;
  }

  /** Deletes an imported WAD; a selection pointing at it falls back to the built-in. */
  deleteWad(path: string): void {
    this.wadRepo.delete(path);
    this.rebuildWads();
    this.notify();
  }

  /** Imports a picked soundfont (by picker uri) and makes it the active one; resolves to its name. */
  async importSoundfont(uri: string): Promise<string> {
    const name = await this.sfRepo.importFrom(uri);
    this.customName = name;
    // Overwriting the custom file while the engine is running it (even under the
    // same name) changes its content — still needs a restart.
    if (this.appliedSoundfont !== '') {
      this.soundfontReplaced = true;
    }
    this.soundfont = name;
    this.notify();
    return name;
  }

  /** Switches to the bundled General MIDI — non-destructive, the custom file is kept. */
  useBuiltinSoundfont(): void {
    this.soundfont = '';
    this.notify();
  }

  /** Switches to the custom soundfont, when one is available. */
  useCustomSoundfont(): void {
    if (this.sfRepo.exists()) {
      this.soundfont = this.customLabel();
      this.notify();
    }
  }

  /**
   * Deletes the custom soundfont file and reverts to General MIDI. Returns false if
   * the file couldn't be removed — the state is left untouched so it stays truthful.
   */
  deleteCustomSoundfont(): boolean {
    if (!this.sfRepo.remove()) {
      return false;
    }
    this.soundfont = '';
    this.customName = '';
    this.notify();
    return true;
  }

  /** Persists the current selection to settings.json; returns false if the save failed. */
  persist(): boolean {
    const s: Settings = {
      version: SETTINGS_VERSION,
      iwad: this.selectedPath,
      soundfont: this.soundfont,
      customSoundfont: this.customName,
    };
    return this.store.save(s);
  }
}
