import { fileIo as fs } from '@kit.CoreFileKit';

/**
 * Manages the optional side-loaded `soundfont.sf2` in the sandbox, which the
 * engine loads in preference to the bundled General MIDI soundfont. Pure file IO.
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
    const src = fs.openSync(uri, fs.OpenMode.READ_ONLY);
    fs.copyFileSync(src.fd, this.path);
    fs.closeSync(src);
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
