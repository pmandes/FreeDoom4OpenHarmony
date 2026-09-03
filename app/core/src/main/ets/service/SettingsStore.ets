import { fileIo as fs } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Settings } from '../model/GameSettings';

const DOMAIN = 0x0000;

/**
 * Reads and writes the user's settings.json in the app sandbox. Pure file IO —
 * no UI, no engine; construct with the ability's filesDir.
 */
export class SettingsStore {
  private readonly path: string;

  private readonly tmpPath: string;

  constructor(filesDir: string) {
    this.path = filesDir + '/settings.json';
    this.tmpPath = filesDir + '/settings.json.tmp';
  }

  /**
   * Loads settings; returns an empty object when the file is absent, unreadable, or
   * not a valid settings object. Each field is validated at runtime so malformed
   * JSON (null, an array, wrong-typed fields) can't crash the caller at startup.
   */
  load(): Settings {
    try {
      const txt = fs.readTextSync(this.path);
      const parsed = JSON.parse(txt) as Settings;
      if (parsed === null || typeof parsed !== 'object') {
        return {};
      }
      const clean: Settings = {};
      if (typeof parsed.version === 'number') {
        clean.version = parsed.version;
      }
      if (typeof parsed.iwad === 'string') {
        clean.iwad = parsed.iwad;
      }
      if (typeof parsed.soundfont === 'string') {
        clean.soundfont = parsed.soundfont;
      }
      if (typeof parsed.customSoundfont === 'string') {
        clean.customSoundfont = parsed.customSoundfont;
      }
      return clean;
    } catch (err) {
      return {};
    }
  }

  /**
   * Persists settings atomically. Writes a temp file, closes it, then renames it
   * over settings.json — so a failed write never truncates the last valid config.
   * Returns false if the save failed (the old settings are left intact).
   */
  save(settings: Settings): boolean {
    let file: fs.File | undefined = undefined;
    try {
      file = fs.openSync(this.tmpPath,
        fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, JSON.stringify(settings));
      fs.closeSync(file);
      file = undefined; // closed — don't double-close in the error handler
      fs.renameSync(this.tmpPath, this.path); // atomic replace
      return true;
    } catch (err) {
      hilog.error(DOMAIN, 'Doom4OH', 'SettingsStore.save failed: %{public}s', JSON.stringify(err));
      if (file !== undefined) {
        try {
          fs.closeSync(file);
        } catch (e) {
          // already closing down — nothing to do
        }
      }
      try {
        fs.unlinkSync(this.tmpPath); // drop the partial temp
      } catch (e) {
        // no temp to remove
      }
      return false;
    }
  }
}
