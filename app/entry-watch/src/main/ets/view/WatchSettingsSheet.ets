import { ArcList, ArcListItem, ArcScrollBar } from '@kit.ArkUI';
import { WadEntry } from 'core';
import { DownloadableWad, DOWNLOADABLE_WADS } from '../service/WadDownloader';

/**
 * The watch settings overlay: an arc list of IWAD slots (or the download list),
 * a floating header, and the round action buttons. Presentation only — it renders
 * a snapshot passed as @Prop and reports intents through callbacks. The download,
 * selection, delete and persistence all live in the WatchSettingsViewModel.
 */
@Component
export struct WatchSettingsSheet {
  @Prop wads: WadEntry[];
  @Prop selectedPath: string;
  @Prop deletePath: string;         // '' = not in delete mode; otherwise the armed path
  @Prop downloadMode: boolean;
  @Prop downloadingFile: string;    // zip name currently downloading ('' = idle)
  @Prop downloadPct: number;
  onSelectWad: (path: string) => void = () => {};
  onArmDelete: (path: string) => void = () => {};
  onDownload: (item: DownloadableWad) => void = () => {};
  onEnterDownload: () => void = () => {};
  onExitDownload: () => void = () => {};
  onCancelDelete: () => void = () => {};
  onConfirmDelete: () => void = () => {};
  onApply: () => void = () => {};
  onClose: () => void = () => {};

  private listScroller: Scroller = new Scroller(); // shared by both lists (only one visible at a time)

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      // Full-height arc list - it goes UNDER the header so that ArcScrollBar
      // matches the curvature of the whole circle (tele4watch pattern: default
      // scrollBar off, dedicated arc bar on the right).
      if (true) {
        if (this.downloadMode) {
          Stack() {
          ArcList({ scroller: this.listScroller, initialIndex: 0 }) {
            ForEach(DOWNLOADABLE_WADS, (d: DownloadableWad) => {
              ArcListItem() {
                Button() {
                  Column({ space: 1 }) {
                    Text(this.downloadingFile === d.zip ? `${d.label}  ${this.downloadPct}%` : d.label)
                      .fontSize(12)
                      .fontWeight(FontWeight.Medium)
                      .fontColor('#E6FFFFFF')
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    Text(this.downloadingFile === d.zip ? 'installing…' : `${d.mb} MB`)
                      .fontSize(9)
                      .fontColor('#80FFFFFF')
                  }
                  .justifyContent(FlexAlign.Center)
                  .padding({ left: 12, right: 12 })
                }
                .width('82%')
                .height(40)
                .borderRadius(20)
                .linearGradient({
                  direction: GradientDirection.RightBottom,
                  colors: this.downloadingFile === d.zip
                    ? [['#2A8FB8', 0.0], ['#12466B', 1.0]]
                    : [['#3A3A3A', 0.0], ['#1E1E1E', 1.0]]
                })
                .opacity(this.downloadingFile !== '' && this.downloadingFile !== d.zip ? 0.4 : 0.9)
                .onClick(() => {
                  this.onDownload(d);
                })
              }
              .margin({ top: 2, bottom: 2 })
            }, (d: DownloadableWad) => d.zip)
          }
          .width('100%')
          .height('100%')
          .scrollBar(BarState.Off)
          ArcScrollBar({ scroller: this.listScroller, state: BarState.Auto })
          }
          .width('100%')
          .height('100%')
        } else {
          Stack() {
          ArcList({ scroller: this.listScroller, initialIndex: 0 }) {
            ForEach(this.wads, (w: WadEntry) => {
              ArcListItem() {
                Button() {
                  Row({ space: 6 }) {
                    if ((this.deletePath !== '' && this.deletePath === w.path)) {
                      Text('🗑')
                        .fontSize(14)
                    }
                    Text(w.name)
                      .fontSize(12)
                      .fontWeight(FontWeight.Medium)
                      .fontColor((this.deletePath !== '' && this.deletePath === w.path)
                        ? '#FF6B6B'
                        : (this.selectedPath === w.path ? '#FFC93C' : '#E6FFFFFF'))
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .layoutWeight(1)
                      .textAlign(TextAlign.Center)
                    if (this.selectedPath === w.path && this.deletePath === '') {
                      Text('✓').fontSize(12).fontColor('#FFC93C')
                    }
                  }
                  .justifyContent(FlexAlign.Center)
                  .padding({ left: 14, right: 14 })
                }
                .width('82%')
                .height(38)
                .borderRadius(19)
                .linearGradient({
                  direction: GradientDirection.RightBottom,
                  colors: (this.deletePath !== '' && this.deletePath === w.path)
                    ? [['#7A2E2E', 0.0], ['#4A1616', 1.0]]
                    : (this.selectedPath === w.path
                      ? [['#8A6A1F', 0.0], ['#5C4610', 1.0]]
                      : [['#3A3A3A', 0.0], ['#242424', 1.0]])
                })
                .opacity(0.92)
                .onClick(() => {
                  this.onSelectWad(w.path);
                })
                // Long-press on a downloaded WAD (not the built-in) = delete mode.
                .gesture(LongPressGesture({ duration: 500 }).onAction(() => {
                  this.onArmDelete(w.path);
                }))
              }
              .margin({ top: 2, bottom: 2 })
            }, (w: WadEntry) => w.path + w.name)
          }
          .width('100%')
          .height('100%')
          .scrollBar(BarState.Off)
          ArcScrollBar({ scroller: this.listScroller, state: BarState.Auto })
          }
          .width('100%')
          .height('100%')
        }
      }

      // Header as an overlay at the top edge (it doesn't take height from the
      // list - so ArcList stays at 100% and the scroll keeps its curvature).
      Column() {
        Text(this.downloadMode ? 'Download WAD' : 'Select IWAD')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)
          .padding({ left: 16, right: 16, top: 5, bottom: 5 })
          .backgroundColor('#CC0A0A0A')
          .borderRadius(14)
          .margin({ top: 14 })
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Start)
      .hitTestBehavior(HitTestMode.None)

      // Round action buttons floating over the list - pattern from the
      // Telegram 4 watch CallScreen. Arranged along an arc (sides raised =
      // "smile") so left/right don't stick out past the round screen at the bottom.
      Row({ space: this.downloadMode ? 28 : 18 }) {
        // ✕ / back - raised along the arc in slot mode; inline in Download.
        Button({ type: ButtonType.Circle }) {
          Text('×')
            .fontSize(30)
            .fontWeight(FontWeight.Bold)
            .fontColor('#F2FFFFFF')
        }
        .width(54)
        .height(54)
        .borderRadius(27)
        .linearGradient({
          direction: GradientDirection.Bottom,
          colors: [['#E5544F', 0.0], ['#A62823', 1.0]]
        })
        .opacity(0.82)
        .border({ width: 1, color: '#33FFFFFF' })
        .shadow({ color: '#59000000', radius: 12, offsetX: 0, offsetY: 4 })
        .offset({ y: this.downloadMode ? 0 : -26 })
        .onClick(() => {
          if (this.deletePath !== '') {
            this.onCancelDelete(); // cancel delete
          } else if (this.downloadMode) {
            this.onExitDownload();
          } else {
            this.onClose();
          }
        })

        // Blue (enter Download) only in the slot view, outside delete mode.
        // In Download mode only ✕ (back) remains.
        if (!this.downloadMode && this.deletePath === '') {
          // Download - center, lowest: switches to the download list.
          Button({ type: ButtonType.Circle }) {
            Column({ space: 2 }) {
              Text('↓').fontSize(20).fontWeight(FontWeight.Bold).fontColor('#F2FFFFFF')
              Divider().width(18).strokeWidth(2).color('#F2FFFFFF')
            }
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
          }
          .width(54)
          .height(54)
          .borderRadius(27)
          .linearGradient({
            direction: GradientDirection.Bottom,
            colors: [['#3AA6CE', 0.0], ['#15597F', 1.0]]
          })
          .opacity(0.82)
          .border({ width: 1, color: '#33FFFFFF' })
          .shadow({ color: '#59000000', radius: 12, offsetX: 0, offsetY: 4 })
          .onClick(() => {
            this.onEnterDownload();
          })
        }

        // Green ✓ - in the slot view: Apply; in delete mode: confirm the
        // deletion. Hidden in Download mode.
        if (!this.downloadMode) {
          Button({ type: ButtonType.Circle }) {
            Text('✓')
              .fontSize(22)
              .fontWeight(FontWeight.Bold)
              .fontColor('#F2FFFFFF')
          }
          .width(54)
          .height(54)
          .borderRadius(27)
          .linearGradient({
            direction: GradientDirection.Bottom,
            colors: [['#5AC15E', 0.0], ['#2E7D33', 1.0]] // always green (OK/confirm)
          })
          .opacity(0.82)
          .border({ width: 1, color: '#33FFFFFF' })
          .shadow({ color: '#59000000', radius: 12, offsetX: 0, offsetY: 4 })
          .offset({ y: -26 })
          .onClick(() => {
            if (this.deletePath !== '') {
              this.onConfirmDelete();
            } else {
              this.onApply();
            }
          })
        }
      }
      .alignItems(VerticalAlign.Center)
      .justifyContent(FlexAlign.Center)
      .margin({ bottom: 14 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F2101010')
  }
}
