/** Persisted user settings (settings.json in the app sandbox). */
export interface Settings {
  iwad?: string;      // absolute path of the chosen IWAD; '' / absent = built-in Freedoom
  soundfont?: string; // display name of the side-loaded soundfont; '' / absent = bundled GM
}

/** One IWAD entry the UI can list and select. */
export interface WadEntry {
  name: string; // display name (file name, or a friendly label for the built-in)
  path: string; // absolute path; '' = built-in Freedoom
}
