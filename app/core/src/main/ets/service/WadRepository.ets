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

  /**
   * Safe destination file name for a picked uri: decode first, then take the
   * basename, so encoded separators (%2F, %2E%2E) can't reintroduce path components
   * that escape the wads directory. Falls back to 'import.wad' for a non-WAD or
   * traversal-shaped name.
   */
  private safeWadName(uri: string): string {
    let decoded: string;
    try {
      decoded = decodeURIComponent(uri);
    } catch (err) {
      decoded = uri; // malformed encoding — the basename below still sanitises it
    }
    const slash = Math.max(decoded.lastIndexOf('/'), decoded.lastIndexOf('\\'));
    const base = slash >= 0 ? decoded.substring(slash + 1) : decoded;
    if (base === '' || base === '.' || base === '..'
        || base.indexOf('/') >= 0 || base.indexOf('\\') >= 0
        || !base.toLowerCase().endsWith('.wad')) {
      return 'import.wad';
    }
    return base;
  }

  /** Copies a picked WAD (by picker uri) into the sandbox; returns its file name. */
  importFrom(uri: string): string {
    this.ensureDir(); // usable standalone — don't assume list() ran first
    const name = this.safeWadName(uri);
    const dest = `${this.dir}/${name}`;
    const tmp = `${dest}.import.tmp`;
    const src = fs.openSync(uri, fs.OpenMode.READ_ONLY);
    try {
      // Copy to a temp file and atomically rename it into place. A failed copy then
      // can't truncate an existing WAD, and a same-name re-import of the running IWAD
      // (which the engine keeps open and reads lumps from lazily) isn't corrupted —
      // the open file keeps the old inode while the new one takes the name.
      fs.copyFileSync(src.fd, tmp);
      fs.renameSync(tmp, dest);
    } catch (err) {
      try {
        fs.unlinkSync(tmp); // drop the partial temp
      } catch (e) {
        // no temp to remove
      }
      throw err as Error;
    } finally {
      // Close even if the copy threw, so repeated failed imports can't leak fds.
      fs.closeSync(src);
    }
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
