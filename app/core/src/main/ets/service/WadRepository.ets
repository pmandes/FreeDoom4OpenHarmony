import { fileIo as fs } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { WadEntry } from '../model/GameSettings';

const DOMAIN = 0x0000;

/**
 * Manages IWAD files under `<filesDir>/wads` in the sandbox: scanning, importing
 * a picked file, and deleting. The built-in Freedoom is not a file here — the
 * caller prepends it to the list with its own label.
 */
export class WadRepository {
  private readonly dir: string;

  constructor(filesDir: string) {
    this.dir = filesDir + '/wads';
  }

  /** Absolute directory holding imported WADs. */
  wadsDir(): string {
    return this.dir;
  }

  private ensureDir(): void {
    try {
      fs.mkdirSync(this.dir);
    } catch (err) {
      // already exists — OK
    }
  }

  /** Every `.wad` in the sandbox, sorted, as name/path entries (excludes the built-in). */
  list(): WadEntry[] {
    this.ensureDir();
    let files: string[] = [];
    try {
      files = fs.listFileSync(this.dir)
        .filter((f: string) => f.toLowerCase().endsWith('.wad'))
        .sort();
    } catch (err) {
      hilog.error(DOMAIN, 'Doom4OH', 'WadRepository.list failed: %{public}s', JSON.stringify(err));
    }
    const entries: WadEntry[] = [];
    for (const f of files) {
      entries.push({ name: f, path: `${this.dir}/${f}` });
    }
    return entries;
  }

  /** Copies a picked WAD (by picker uri) into the sandbox; returns its file name. */
  importFrom(uri: string): string {
    const name = decodeURIComponent(uri.split('/').pop() ?? 'import.wad');
    const src = fs.openSync(uri, fs.OpenMode.READ_ONLY);
    fs.copyFileSync(src.fd, `${this.dir}/${name}`);
    fs.closeSync(src);
    return name;
  }

  /** Deletes an imported WAD by absolute path. */
  delete(path: string): void {
    try {
      fs.unlinkSync(path);
    } catch (err) {
      // already gone — OK
    }
  }
}
