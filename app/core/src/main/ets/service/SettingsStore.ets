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

  constructor(filesDir: string) {
    this.path = filesDir + '/settings.json';
  }

  /** Loads settings; returns an empty object when the file is absent or unreadable. */
  load(): Settings {
    try {
      const txt = fs.readTextSync(this.path);
      return JSON.parse(txt) as Settings;
    } catch (err) {
      return {};
    }
  }

  /** Persists settings, replacing the file. */
  save(settings: Settings): void {
    try {
      const file = fs.openSync(this.path,
        fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, JSON.stringify(settings));
      fs.closeSync(file);
    } catch (err) {
      hilog.error(DOMAIN, 'Doom4OH', 'SettingsStore.save failed: %{public}s', JSON.stringify(err));
    }
  }
}
