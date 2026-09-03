import { Settings, WadEntry, SettingsStore, WadRepository, SoundfontRepository } from 'core';

/** Notifies the view that settings state changed (it re-reads the snapshot). */
export type SettingsListener = () => void;

/** Label for the bundled Freedoom, which is not a file in the sandbox. */
const BUILT_IN_WAD_LABEL = 'Freedoom (built-in)';

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
  private soundfont: string = '';

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

  /** Display name of the active soundfont ('' = bundled General MIDI). */
  soundfontName(): string {
    return this.soundfont;
  }

  // ── Operations ─────────────────────────────────────────────────────────────

  /** Loads persisted settings and scans the sandbox. Call once it is available. */
  load(): void {
    const s = this.store.load();
    this.selectedPath = s.iwad ?? '';
    this.soundfont = s.soundfont ?? '';
    // Reconcile the recorded name with what is actually on disk: a wiped sandbox
    // leaves the name dangling, while a soundfont.sf2 pushed over hdc has no name.
    const hasFile = this.sfRepo.exists();
    if (this.soundfont !== '' && !hasFile) {
      this.soundfont = '';
    } else if (this.soundfont === '' && hasFile) {
      this.soundfont = 'Custom soundfont';
    }
    this.rebuildWads();
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
    this.selectedPath = path;
    this.notify();
  }

  /** Imports a picked WAD (by picker uri); returns its file name. */
  importWad(uri: string): string {
    const name = this.wadRepo.importFrom(uri);
    this.rebuildWads();
    this.notify();
    return name;
  }

  /** Imports a picked soundfont (by picker uri) as the active custom one; returns its name. */
  importSoundfont(uri: string): string {
    const name = this.sfRepo.importFrom(uri);
    this.soundfont = name;
    this.notify();
    return name;
  }

  /** Drops the custom soundfont so the engine falls back to the bundled GM one. */
  removeSoundfont(): void {
    this.sfRepo.remove();
    this.soundfont = '';
    this.notify();
  }

  /** Persists the current selection to settings.json (takes effect on restart). */
  persist(): void {
    const s: Settings = { iwad: this.selectedPath, soundfont: this.soundfont };
    this.store.save(s);
  }
}
