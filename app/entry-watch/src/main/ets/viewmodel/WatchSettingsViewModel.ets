import { Settings, WadEntry, SettingsStore, WadRepository } from 'core';
import { DownloadableWad, WadDownloader } from '../service/WadDownloader';

/** Notifies the view that settings state changed (it re-reads the snapshot). */
export type SettingsListener = () => void;

/** Label for the bundled Freedoom, which is not a file in the sandbox. */
const BUILT_IN_WAD_LABEL = 'Freedoom (built-in)';

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

/**
 * Presentation state and operations for the watch settings overlay: the IWAD
 * slot list (with friendly titles) and selection, long-press delete, and the
 * download list with progress. Plain class with a change listener (Telegram
 * viewmodel style) — the view mirrors the snapshot into @State. Holds the core
 * repositories and the download service; the pause/restart stay in the view.
 */
export class WatchSettingsViewModel {
  private readonly store: SettingsStore;
  private readonly wadRepo: WadRepository;
  private readonly downloader: WadDownloader;
  private listener?: SettingsListener;

  private wadList: WadEntry[] = [{ name: BUILT_IN_WAD_LABEL, path: '' }];
  private selectedPath: string = '';
  private deletePath: string = '';        // '' = not armed; otherwise the path armed for deletion
  private downloadMode: boolean = false;  // showing the download list instead of the slot list
  private downloadingFile: string = '';   // zip name currently downloading ('' = idle)
  private downloadPct: number = 0;

  constructor(filesDir: string) {
    this.store = new SettingsStore(filesDir);
    this.wadRepo = new WadRepository(filesDir);
    this.downloader = new WadDownloader(filesDir, this.wadRepo.wadsDir());
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

  /** The IWAD slot list: built-in first, then imported WADs (friendly titles). */
  wads(): WadEntry[] {
    return this.wadList;
  }

  /** Absolute path of the active IWAD ('' = built-in). */
  selection(): string {
    return this.selectedPath;
  }

  /** Path armed for deletion by a long press ('' = none). */
  armedForDelete(): string {
    return this.deletePath;
  }

  /** True while the download list is showing instead of the slot list. */
  isDownloadMode(): boolean {
    return this.downloadMode;
  }

  /** Zip name currently downloading ('' = idle). */
  downloadingZip(): string {
    return this.downloadingFile;
  }

  /** Download/unpack progress as a whole percentage. */
  downloadPercent(): number {
    return this.downloadPct;
  }

  // ── Operations ─────────────────────────────────────────────────────────────

  /** Loads persisted settings and scans the sandbox. Call once it is available. */
  load(): void {
    this.selectedPath = this.store.load().iwad ?? '';
    this.refreshWads();
    this.notify();
  }

  /** Rescans imported WADs (e.g. when the settings overlay opens). */
  rescan(): void {
    this.refreshWads();
    this.notify();
  }

  private refreshWads(): void {
    const entries: WadEntry[] = [{ name: BUILT_IN_WAD_LABEL, path: '' }];
    for (const e of this.wadRepo.list()) {
      entries.push({ name: wadTitle(e.name), path: e.path });
    }
    this.wadList = entries;
    // A selection pointing at a deleted file falls back to the built-in.
    if (this.selectedPath !== '' && !entries.some((e: WadEntry) => e.path === this.selectedPath)) {
      this.selectedPath = '';
    }
  }

  /** Chooses the active IWAD (draft — persisted on apply). Ignored while armed for delete. */
  selectWad(path: string): void {
    if (this.deletePath !== '') {
      return;
    }
    this.selectedPath = path;
    this.notify();
  }

  /** Arms an imported WAD for deletion (long press); the built-in can't be deleted. */
  armDelete(path: string): void {
    if (path !== '') {
      this.deletePath = path;
      this.notify();
    }
  }

  /** Cancels delete mode. */
  cancelDelete(): void {
    this.deletePath = '';
    this.notify();
  }

  /** Deletes the armed WAD; a selection pointing at it falls back to the built-in. */
  confirmDelete(): void {
    const path = this.deletePath;
    this.deletePath = '';
    if (path === '') {
      this.notify();
      return;
    }
    this.wadRepo.delete(path);
    if (this.selectedPath === path) {
      this.selectedPath = ''; // removed selection falls back to Freedoom
    }
    this.refreshWads();
    this.notify();
  }

  /** Switches to the download list. */
  enterDownloadMode(): void {
    this.downloadMode = true;
    this.notify();
  }

  /** Leaves the download list, back to the slot list. */
  exitDownloadMode(): void {
    this.downloadMode = false;
    this.notify();
  }

  /**
   * Downloads and installs a WAD, then selects it and returns to the slot list.
   * Progress is published through the listener; a second call while one is in
   * flight is ignored.
   */
  async download(item: DownloadableWad): Promise<void> {
    if (this.downloadingFile !== '') {
      return;
    }
    this.downloadingFile = item.zip;
    this.downloadPct = 0;
    this.notify();
    const dest = await this.downloader.install(item, (pct: number) => {
      this.downloadPct = pct;
      this.notify();
    });
    if (dest !== '') {
      this.selectedPath = dest;
      this.downloadMode = false;
      this.refreshWads();
    }
    this.downloadingFile = '';
    this.downloadPct = 0;
    this.notify();
  }

  /** Persists the current IWAD selection to settings.json; returns false on failure. */
  persist(): boolean {
    const s: Settings = { iwad: this.selectedPath };
    return this.store.save(s);
  }
}
