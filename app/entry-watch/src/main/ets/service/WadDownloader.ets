import { fileIo as fs } from '@kit.CoreFileKit';
import { http } from '@kit.NetworkKit';
import { zlib } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;

/** A WAD available for download as a ZIP from the remote repo. */
export interface DownloadableWad {
  zip: string;   // ZIP file name in the repo (with spaces)
  label: string; // display title of the game
  mb: number;
}

// WADs available for download as ZIPs (dabignerd/doom-wads repo), unpacked on
// the watch into the sandbox. Only DOOM-engine IWADs (Freedoom included) -
// Heretic/Hexen/Strife/Chex3 have their own engines and doomgeneric won't run them.
export const WAD_ZIP_BASE = 'https://raw.githubusercontent.com/dabignerd/doom-wads/master/zips/';
export const DOWNLOADABLE_WADS: DownloadableWad[] = [
  { zip: 'Freedoom - Phase 1 (v0.12.1).zip', label: 'Freedoom: Phase 1', mb: 9 },
  { zip: 'Freedoom - Phase 2 (v0.12.1).zip', label: 'Freedoom: Phase 2', mb: 10 },
  { zip: 'The Ultimate Doom.zip', label: 'The Ultimate Doom', mb: 5 },
  { zip: 'Doom (v1.9).zip', label: 'Doom', mb: 5 },
  { zip: 'Doom II - Hell on Earth (v1.9).zip', label: 'Doom II: Hell on Earth', mb: 6 },
  { zip: 'Final Doom - The Plutonia Experiment.zip', label: 'Final Doom: Plutonia', mb: 7 },
  { zip: 'Final Doom - TNT - Evilution.zip', label: 'Final Doom: TNT Evilution', mb: 8 },
  { zip: 'Chex Quest.zip', label: 'Chex Quest', mb: 4 },
];

/** Reports download/unpack progress as a whole percentage (0-100). */
export type ProgressHandler = (pct: number) => void;

/**
 * Downloads a WAD ZIP over HTTP, unpacks it and installs the .wad into the
 * sandbox wads/ directory. Pure network/file IO (no UI) — the caller owns the
 * selection and list refresh. The INTERNET permission is system_grant.
 */
export class WadDownloader {
  private readonly filesDir: string;
  private readonly wadsDir: string;
  private foundWadPath: string = '';

  constructor(filesDir: string, wadsDir: string) {
    this.filesDir = filesDir;
    this.wadsDir = wadsDir;
  }

  /**
   * Downloads and installs `item`; resolves to the installed WAD's absolute path,
   * or '' on any failure (logged). `onProgress` is called with 0..100 as the
   * download (0-90) then unpack (92) proceed.
   */
  async install(item: DownloadableWad, onProgress: ProgressHandler): Promise<string> {
    const tmpDir = `${this.filesDir}/dltmp`;
    const zipPath = `${tmpDir}/dl.zip`;
    const unzipDir = `${tmpDir}/out`;
    const request = http.createHttp();
    let file: fs.File | undefined;
    try {
      try { fs.rmdirSync(tmpDir); } catch (e) {}
      fs.mkdirSync(tmpDir);
      fs.mkdirSync(unzipDir);
      file = fs.openSync(zipPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      const fd = file.fd;
      request.on('dataReceive', (chunk: ArrayBuffer) => {
        fs.writeSync(fd, chunk);
      });
      request.on('dataReceiveProgress', (p: http.DataReceiveProgressInfo) => {
        if (p.totalSize > 0) {
          onProgress(Math.floor(p.receiveSize * 90 / p.totalSize)); // 90% = download
        }
      });
      const url = WAD_ZIP_BASE + encodeURIComponent(item.zip);
      const code = await request.requestInStream(url, {
        method: http.RequestMethod.GET, connectTimeout: 30000, readTimeout: 180000,
      });
      fs.closeSync(file);
      file = undefined;
      if (code < 200 || code >= 300) {
        hilog.error(DOMAIN, 'Doom4OH', 'download http %{public}d', code);
        return '';
      }
      onProgress(92); // unpacking
      await zlib.decompressFile(zipPath, unzipDir);
      const wadName = this.findWad(unzipDir);
      if (wadName === '') {
        hilog.error(DOMAIN, 'Doom4OH', 'no wad in zip %{public}s', item.zip);
        return '';
      }
      const dest = `${this.wadsDir}/${wadName}`;
      const src = fs.openSync(this.foundWadPath, fs.OpenMode.READ_ONLY);
      const out = fs.openSync(dest, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fs.copyFileSync(src.fd, out.fd);
      fs.closeSync(src);
      fs.closeSync(out);
      hilog.info(DOMAIN, 'Doom4OH', 'installed %{public}s from %{public}s', wadName, item.zip);
      return dest;
    } catch (err) {
      hilog.error(DOMAIN, 'Doom4OH', 'download failed: %{public}s', JSON.stringify(err));
      if (file !== undefined) {
        try { fs.closeSync(file); } catch (e) {}
      }
      return '';
    } finally {
      request.off('dataReceive');
      request.off('dataReceiveProgress');
      request.destroy();
      try { fs.rmdirSync(tmpDir); } catch (e) {}
    }
  }

  /** Finds the first .wad in the unpacked tree (one directory level deep). */
  private findWad(dir: string): string {
    try {
      const items = fs.listFileSync(dir);
      for (const it of items) {
        if (it.toLowerCase().endsWith('.wad')) {
          this.foundWadPath = `${dir}/${it}`;
          return it;
        }
      }
      for (const it of items) {
        const sub = `${dir}/${it}`;
        try {
          if (fs.statSync(sub).isDirectory()) {
            const inner = fs.listFileSync(sub).find((f: string) => f.toLowerCase().endsWith('.wad'));
            if (inner !== undefined) {
              this.foundWadPath = `${sub}/${inner}`;
              return inner;
            }
          }
        } catch (e) {}
      }
    } catch (err) {
      hilog.error(DOMAIN, 'Doom4OH', 'findWad err: %{public}s', JSON.stringify(err));
    }
    return '';
  }
}
