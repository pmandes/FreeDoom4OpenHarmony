import { WadEntry } from 'core';

/**
 * The settings panel: IWAD selection and the music soundfont. Presentation only —
 * it renders a snapshot passed from the page and reports intents through callbacks.
 * The page owns the view model, the file picker and the app restart.
 */
@Component
export struct SettingsSheet {
  @Prop wads: WadEntry[];
  @Prop selectedPath: string;
  @Prop soundfontName: string;
  onSelectWad: (path: string) => void = () => {};
  onImportWad: () => void = () => {};
  onImportSoundfont: () => void = () => {};
  onRemoveSoundfont: () => void = () => {};
  onApply: () => void = () => {};
  onClose: () => void = () => {};

  /** Text button with a tap handler, used in the panel. */
  @Builder
  actionButton(label: string, onClick: () => void) {
    Text(label)
      .padding({ left: 16, right: 16, top: 10, bottom: 10 })
      .fontSize(15)
      .fontColor('#73FFFFFF')
      .linearGradient({
        angle: 180,
        colors: [['#4DFFFFFF', 0], ['#1FFFFFFF', 0.5], ['#12FFFFFF', 1]]
      })
      .borderRadius(10)
      .border({ width: 1, color: '#1FFFFFFF' })
      .shadow({ radius: 8, color: '#4D000000', offsetX: 0, offsetY: 3 })
      .onClick(onClick)
  }

  build() {
    Column({ space: 14 }) {
      Row() {
        Blank().width(36)
        Text('Select IWAD')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
        Text('✕')
          .width(36)
          .height(36)
          .fontSize(18)
          .fontColor('#B3FFFFFF')
          .textAlign(TextAlign.Center)
          .borderRadius(18)
          .backgroundColor('#22FFFFFF')
          .onClick(() => {
            this.onClose();
          })
      }
      .width('100%')

      List({ space: 4 }) {
        ForEach(this.wads, (w: WadEntry) => {
          ListItem() {
            Row() {
              Text(w.name)
                .fontSize(15)
                .fontColor(this.selectedPath === w.path ? '#FFC93C' : Color.White)
              Blank()
              if (this.selectedPath === w.path) {
                Text('✓').fontSize(15).fontColor('#FFC93C')
              }
            }
            .width('100%')
            .padding({ left: 12, right: 12, top: 8, bottom: 8 })
            .borderRadius(8)
            .backgroundColor(this.selectedPath === w.path ? '#33FFC93C' : '#22FFFFFF')
            .onClick(() => {
              this.onSelectWad(w.path);
            })
          }
        }, (w: WadEntry) => w.path + w.name)
      }
      .width('100%')
      .height(170)

      Row({ space: 10 }) {
        Column() {
          Text('Music soundfont')
            .fontSize(12)
            .fontColor('#80FFFFFF')
          Text(this.soundfontName !== '' ? this.soundfontName : 'General MIDI (built-in)')
            .fontSize(14)
            .fontColor('#E6FFFFFF')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        this.actionButton('Load soundfont…', () => {
          this.onImportSoundfont();
        })
        if (this.soundfontName !== '') {
          this.actionButton('Remove', () => {
            this.onRemoveSoundfont();
          })
        }
      }
      .width('100%')

      Row({ space: 12 }) {
        this.actionButton('Load WAD…', () => {
          this.onImportWad();
        })
        this.actionButton('Apply & Restart', () => {
          this.onApply();
        })
      }
    }
    .width(560)
    .padding(20)
    .backgroundColor('#E6202020')
    .borderRadius(16)
  }
}
