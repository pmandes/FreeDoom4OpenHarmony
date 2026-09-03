import { WadEntry } from 'core';

/** The settings sections, shown in the left rail. */
enum SettingsSection {
  Game,
  Audio,
  Controls,
  About
}

/** One line in the read-only Controls reference. */
interface ControlRow {
  keys: string;
  action: string;
}

const CONTROL_REFERENCE: ControlRow[] = [
  { keys: 'Left stick', action: 'Move — forward / back, strafe' },
  { keys: 'Right stick', action: 'Turn left / right' },
  { keys: 'Fire (red)', action: 'Shoot — also confirms menus' },
  { keys: '◀ ▶', action: 'Previous / next weapon' },
  { keys: 'Tap screen', action: 'Use — doors, switches' },
  { keys: '≡', action: 'Menu (Escape)' },
  { keys: 'Keyboard', action: 'Arrows, Ctrl fire, Space use, Shift run' }
];

/**
 * The settings screen: a sectioned master–detail overlay. The left rail lists
 * sections; the right pane shows the active one. Presentation only — it renders
 * a snapshot passed as @Prop and reports intents through callbacks. Changes that
 * need an engine restart (IWAD, soundfont) collect in a footer that applies once.
 */
@Component
export struct SettingsSheet {
  @Prop wads: WadEntry[];
  @Prop selectedPath: string;
  @Prop soundfontName: string;        // '' = built-in active, non-empty = custom active
  @Prop soundfontAvailable: boolean;  // a custom soundfont file is present
  @Prop soundfontLabel: string;       // display label for the custom soundfont
  @Prop hasPending: boolean;
  @Prop pendingSummary: string;
  @Prop appVersion: string;
  onSelectWad: (path: string) => void = () => {};
  onDeleteWad: (path: string) => void = () => {};
  onImportWad: () => void = () => {};
  onImportSoundfont: () => void = () => {};
  onUseBuiltinSoundfont: () => void = () => {};
  onUseCustomSoundfont: () => void = () => {};
  onDeleteSoundfont: () => void = () => {};
  onApply: () => void = () => {};
  onClose: () => void = () => {};

  @State private activeSection: SettingsSection = SettingsSection.Game;
  @State private deletePath: string = ''; // WAD armed for deletion by a long press ('' = none)

  private sectionTitle(): string {
    switch (this.activeSection) {
      case SettingsSection.Game: return 'Game — IWAD';
      case SettingsSection.Audio: return 'Audio — Soundfont';
      case SettingsSection.Controls: return 'Controls';
      default: return 'About';
    }
  }

  /** A secondary, glass text button. */
  @Builder
  actionButton(label: string, onClick: () => void) {
    Text(label)
      .padding({ left: 15, right: 15, top: 9, bottom: 9 })
      .fontSize(14)
      .fontColor('#CCFFFFFF')
      .linearGradient({
        angle: 180,
        colors: [['#33FFFFFF', 0], ['#14FFFFFF', 0.5], ['#0DFFFFFF', 1]]
      })
      .borderRadius(9)
      .border({ width: 1, color: '#1FFFFFFF' })
      .onClick(onClick)
  }

  /** Current-value hint under a rail label. Read inside the builder so it stays reactive. */
  private railSub(section: SettingsSection): string {
    if (section === SettingsSection.Game) {
      return this.wadName(this.selectedPath);
    }
    if (section === SettingsSection.Audio) {
      return this.soundfontName !== '' ? this.soundfontName : 'General MIDI';
    }
    return '';
  }

  /** A section entry in the left rail. */
  @Builder
  railItem(icon: string, label: string, section: SettingsSection) {
    Row({ space: 9 }) {
      Text(icon)
        .fontSize(14)
        .width(18)
        .textAlign(TextAlign.Center)
        .fontColor(this.activeSection === section ? '#FFC93C' : '#99FFFFFF')
      Column() {
        Text(label)
          .fontSize(14)
          .fontColor(this.activeSection === section ? Color.White : '#D9FFFFFF')
        if (this.railSub(section) !== '') {
          Text(this.railSub(section))
            .fontSize(10)
            .fontColor('#80FFFFFF')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding({ left: 12, right: 10, top: 9, bottom: 9 })
    .borderRadius(8)
    .backgroundColor(this.activeSection === section ? '#26FFC93C' : '#00000000')
    .onClick(() => {
      this.activeSection = section;
      this.deletePath = '';
    })
  }

  /**
   * One IWAD row. Long-press an imported WAD to arm it for deletion (red row +
   * trash); tap the trash to remove it, or tap the row to cancel. Tap otherwise
   * selects the WAD. The built-in cannot be deleted.
   */
  /** True when this WAD row is armed for deletion ('' never matches the built-in). */
  private wadArmed(path: string): boolean {
    return this.deletePath !== '' && this.deletePath === path;
  }

  @Builder
  wadRow(w: WadEntry) {
    Row() {
      Text(w.name)
        .fontSize(15)
        .fontColor(this.selectedPath === w.path && !this.wadArmed(w.path) ? '#FFC93C' : Color.White)
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      if (this.wadArmed(w.path)) {
        Text('🗑')
          .fontSize(16)
          .fontColor('#FF7A6B')
          .padding({ left: 12, right: 4 })
          .onClick(() => {
            this.onDeleteWad(w.path);
            this.deletePath = '';
          })
      } else if (this.selectedPath === w.path) {
        Text('✓').fontSize(15).fontColor('#FFC93C')
      }
    }
    .width('100%')
    .height(42) // fixed so arming (trash icon) can't change the row height
    .padding({ left: 12, right: 12 })
    .borderRadius(8)
    .backgroundColor(this.wadArmed(w.path)
      ? '#4DE0392B'
      : (this.selectedPath === w.path ? '#33FFC93C' : '#14FFFFFF'))
    .gesture(LongPressGesture()
      .onAction(() => {
        if (w.path !== '') {
          this.deletePath = w.path;
        }
      }))
    .onClick(() => {
      if (this.deletePath !== '') {
        this.deletePath = ''; // any tap while a row is armed cancels delete mode
      } else {
        this.onSelectWad(w.path);
      }
    })
  }

  /** Whether the built-in / custom soundfont row is the active one — read inside
   *  the builder so the checkmark stays reactive (an @Builder param would not). */
  private soundfontActive(isBuiltIn: boolean): boolean {
    return isBuiltIn ? this.soundfontName === '' : this.soundfontName !== '';
  }

  /** A selectable soundfont row. isBuiltIn picks the General MIDI vs custom slot. */
  @Builder
  soundfontRow(label: string, sub: string, isBuiltIn: boolean, onClick: () => void) {
    Row() {
      Column() {
        Text(label)
          .fontSize(15)
          .fontColor(this.soundfontActive(isBuiltIn) ? '#FFC93C' : Color.White)
        Text(sub)
          .fontSize(11)
          .fontColor('#80FFFFFF')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      if (this.soundfontActive(isBuiltIn)) {
        Text('✓').fontSize(15).fontColor('#FFC93C')
      }
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 9, bottom: 9 })
    .borderRadius(8)
    .backgroundColor(this.soundfontActive(isBuiltIn) ? '#33FFC93C' : '#14FFFFFF')
    .onClick(onClick)
  }

  @Builder
  gameSection() {
    List({ space: 4 }) {
      ForEach(this.wads, (w: WadEntry) => {
        ListItem() {
          this.wadRow(w)
        }
      }, (w: WadEntry) => w.path + w.name)
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  audioSection() {
    Column({ space: 6 }) {
      this.soundfontRow('General MIDI — TimGM6mb', 'Bundled, 6 MB', true, () => {
        this.onUseBuiltinSoundfont();
      })
      if (this.soundfontAvailable) {
        this.soundfontRow(this.soundfontLabel, 'Side-loaded .sf2', false, () => {
          this.onUseCustomSoundfont();
        })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  /** Section-specific actions, pinned to the bottom of the window. */
  @Builder
  actionBar() {
    Row({ space: 10 }) {
      if (this.activeSection === SettingsSection.Game) {
        this.actionButton('+ Import WAD…', () => {
          this.onImportWad();
        })
      } else if (this.activeSection === SettingsSection.Audio) {
        this.actionButton('+ Load .sf2…', () => {
          this.onImportSoundfont();
        })
        if (this.soundfontAvailable) {
          Text('Remove custom')
            .fontSize(13)
            .fontColor('#E8897F')
            .padding({ left: 12, right: 12, top: 9, bottom: 9 })
            .borderRadius(9)
            .border({ width: 1, color: '#33E8897F' })
            .onClick(() => {
              this.onDeleteSoundfont();
            })
        }
      }
    }
    .width('100%')
    .height(44)
    .margin({ top: 8 })
    .justifyContent(FlexAlign.End)
  }

  @Builder
  controlsSection() {
    Column({ space: 8 }) {
      ForEach(CONTROL_REFERENCE, (c: ControlRow) => {
        Row() {
          Text(c.keys)
            .fontSize(13)
            .fontColor('#FFC93C')
            .width(110)
          Text(c.action)
            .fontSize(13)
            .fontColor('#D9FFFFFF')
            .layoutWeight(1)
        }
        .width('100%')
      }, (c: ControlRow) => c.keys)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  aboutSection() {
    Column({ space: 10 }) {
      Text('FreeDoom4OpenHarmony')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor(Color.White)
      Text(`Engine: ${this.appVersion}`)
        .fontSize(13)
        .fontColor('#D9FFFFFF')
      Text('doomgeneric + Freedoom · MIDI music via FluidLite')
        .fontSize(13)
        .fontColor('#A6FFFFFF')
      Text('An unofficial, non-commercial fan port. GPLv2.')
        .fontSize(12)
        .fontColor('#80FFFFFF')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    // Stack so the pending footer floats over the content instead of pushing it
    // up: the base layer reserves a bottom strip, the footer overlays it.
    Stack({ alignContent: Alignment.Bottom }) {
      Column() {
        // Header
        Row() {
          Text('Settings')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
            .layoutWeight(1)
          Text('✕')
            .width(34)
            .height(34)
            .fontSize(17)
            .fontColor('#B3FFFFFF')
            .textAlign(TextAlign.Center)
            .borderRadius(17)
            .backgroundColor('#22FFFFFF')
            .onClick(() => {
              this.onClose();
            })
        }
        .width('100%')
        .margin({ bottom: 12 })

        // Body: rail + detail
        Row({ space: 14 }) {
          // Left rail
          Column({ space: 3 }) {
            this.railItem('◆', 'Game', SettingsSection.Game)
            this.railItem('♪', 'Audio', SettingsSection.Audio)
            this.railItem('⛓', 'Controls', SettingsSection.Controls)
            this.railItem('ⓘ', 'About', SettingsSection.About)
          }
          .width(196)
          .alignItems(HorizontalAlign.Start)

          // Detail pane
          Column() {
            Text(this.sectionTitle())
              .fontSize(13)
              .fontColor('#80FFFFFF')
              .width('100%')
              .textAlign(TextAlign.Start)
              .margin({ bottom: 8 })
            if (this.activeSection === SettingsSection.Game) {
              this.gameSection()
            } else if (this.activeSection === SettingsSection.Audio) {
              this.audioSection()
            } else if (this.activeSection === SettingsSection.Controls) {
              this.controlsSection()
            } else {
              this.aboutSection()
            }
          }
          .layoutWeight(1)
          .height('100%')
          .alignItems(HorizontalAlign.Start)
        }
        .layoutWeight(1)
        .width('100%')
        .alignItems(VerticalAlign.Top)

        // Section actions, pinned to the bottom so the list keeps the full height.
        this.actionBar()
      }
      .width('100%')
      .height('100%')

      // Pending-changes footer — overlays the action bar, so showing or hiding
      // it never reflows the content above.
      if (this.hasPending) {
        Row({ space: 11 }) {
          Column()
            .width(8)
            .height(8)
            .borderRadius(4)
            .backgroundColor('#E0A83B')
          Text(`Restart to apply: ${this.pendingSummary}`)
            .fontSize(13)
            .fontColor('#E0A83B')
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text('Restart')
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontColor('#161009')
            .padding({ left: 16, right: 16, top: 8, bottom: 8 })
            .borderRadius(8)
            .backgroundColor('#E0A83B')
            .onClick(() => {
              this.onApply();
            })
        }
        .width('100%')
        .padding(10)
        .borderRadius(9)
        .backgroundColor('#F0261D08') // opaque: covers the action bar it overlays
        .border({ width: 1, color: '#66E0A83B' })
      }
    }
    .width('82%')
    .height('84%')
    .padding({ top: 20, left: 22, right: 22, bottom: 24 })
    .backgroundColor('#F2202020')
    .borderRadius(16)
  }

  private wadName(path: string): string {
    if (path === '') {
      return 'Freedoom (built-in)';
    }
    for (const w of this.wads) {
      if (w.path === path) {
        return w.name;
      }
    }
    return path;
  }
}
