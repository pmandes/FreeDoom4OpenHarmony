/** Persisted user settings (settings.json in the app sandbox). */
export interface Settings {
  // Schema version. Absent = legacy (pre-MVVM) file, where soundfont: '' was written
  // routinely and a side-loaded soundfont.sf2 was still auto-detected; such files are
  // migrated on read. Present (>= 1) = a soundfont: '' is an explicit built-in choice.
  version?: number;
  iwad?: string; // absolute path of the chosen IWAD; '' / absent = built-in Freedoom
  // Soundfont choice — the three states are distinct, so do not conflate absent with '':
  //   undefined (key absent) = never chosen; the app auto-detects a side-loaded file,
  //   ''                      = explicitly the bundled General MIDI (see version above),
  //   non-empty               = the custom soundfont (its display name).
  soundfont?: string;
  // Display name of the side-loaded custom soundfont, kept even while built-in is
  // active so its label survives a switch-to-built-in and restart.
  customSoundfont?: string;
}

/** One IWAD entry the UI can list and select. */
export interface WadEntry {
  name: string; // display name (file name, or a friendly label for the built-in)
  path: string; // absolute path; '' = built-in Freedoom
}
