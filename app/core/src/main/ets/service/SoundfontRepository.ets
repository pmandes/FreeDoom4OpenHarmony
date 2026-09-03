import { fileIo as fs } from '@kit.CoreFileKit';

/**
 * Manages the optional custom `soundfont.sf2` in the sandbox. Pure file IO — it
 * only stores the file; whether the engine uses it is decided by the caller
 * (settings.json / the soundfont path passed to startGame), not by file presence.
 */
export class SoundfontRepository {
  private readonly path: string;

  constructor(filesDir: string) {
    this.path = filesDir + '/soundfont.sf2';
  }

  /** Absolute path of the custom soundfont slot. */
  filePath(): string {
    return this.path;
  }

  /** True when a custom soundfont is present. */
  exists(): boolean {
    try {
      fs.accessSync(this.path);
      return true;
    } catch (err) {
      return false;
    }
  }

  /** Copies a picked `.sf2` (by picker uri) over the custom slot; returns its file name. */
  importFrom(uri: string): string {
    const name = decodeURIComponent(uri.split('/').pop() ?? 'soundfont.sf2');
    const tmp = `${this.path}.import.tmp`;
    const src = fs.openSync(uri, fs.OpenMode.READ_ONLY);
    try {
      // Copy to a temp file and atomically rename it into place, so a failed copy of
      // a large .sf2 can't truncate the previous valid soundfont.
      fs.copyFileSync(src.fd, tmp);
      fs.renameSync(tmp, this.path);
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

  /** Removes the custom soundfont so the engine falls back to the bundled GM one. */
  remove(): void {
    try {
      fs.unlinkSync(this.path);
    } catch (err) {
      // already gone — OK
    }
  }
}
