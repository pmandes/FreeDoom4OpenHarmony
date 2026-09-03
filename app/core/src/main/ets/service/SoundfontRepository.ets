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
      // Match the native startGame contract: a regular, non-empty file. A missing
      // path makes statSync throw; a directory or zero-byte file would be rejected
      // by the engine (it needs st_size > 0), so don't report it as available here.
      // (accessSync is unreliable in this SDK: it can return without throwing for a
      // missing path, so it would keep reporting a deleted soundfont as present.)
      const st = fs.statSync(this.path);
      return st.isFile() && st.size > 0;
    } catch (err) {
      return false;
    }
  }

  /** Copies a picked `.sf2` (by picker uri) over the custom slot; resolves to its file name. */
  async importFrom(uri: string): Promise<string> {
    const base = uri.split('/').pop() ?? 'soundfont.sf2';
    let name: string;
    try {
      name = decodeURIComponent(base);
    } catch (err) {
      // Malformed percent-encoding: this name is only the display label (the file
      // always goes to the fixed slot), so keep the raw basename instead of aborting.
      name = base;
    }
    const tmp = `${this.path}.import.tmp`;
    const src = await fs.open(uri, fs.OpenMode.READ_ONLY);
    try {
      // Copy with the async fileIo API so a large .sf2 (tens of MB) doesn't block the
      // UI thread, then atomically rename it into place, so a failed copy can't
      // truncate the previous valid soundfont.
      await fs.copyFile(src.fd, tmp);
      // A zero-byte or non-regular copy would be rejected by exists() and the native
      // engine (which needs st_size > 0), yet the rename would still clobber a good
      // soundfont with a dud. Validate the temp before committing it; the catch drops it.
      const st = await fs.stat(tmp);
      if (!st.isFile() || st.size === 0) {
        throw new Error('imported soundfont is empty');
      }
      await fs.rename(tmp, this.path);
    } catch (err) {
      try {
        await fs.unlink(tmp); // drop the partial temp
      } catch (e) {
        // no temp to remove
      }
      throw err as Error;
    } finally {
      // Close even if the copy threw, so repeated failed imports can't leak fds.
      await fs.close(src);
    }
    return name;
  }

  /**
   * Removes the custom soundfont. Returns true when the file is gone afterwards
   * (deleted, or already absent), false when a real failure left it in place — the
   * post-state is checked directly, so a genuine I/O/permission error isn't mistaken
   * for "already gone".
   */
  remove(): boolean {
    try {
      fs.unlinkSync(this.path);
    } catch (err) {
      // Ignore here — exists() below is the source of truth (ENOENT vs a real error).
    }
    return !this.exists();
  }
}
