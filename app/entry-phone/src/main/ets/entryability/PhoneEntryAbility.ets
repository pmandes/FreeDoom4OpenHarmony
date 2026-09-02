import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';

const DOMAIN = 0x0000;

/** Main UIAbility: sets up immersive landscape and loads the game page. */
export default class PhoneEntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, 'Doom4OH', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
    hilog.info(DOMAIN, 'Doom4OH', '%{public}s', 'Ability onCreate');
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'Doom4OH', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, 'Doom4OH', '%{public}s', 'Ability onWindowStageCreate');

    // Ability context for the page (preferences rejects the one from getHostContext()).
    AppStorage.setOrCreate('abilityContext', this.context);

    // Configure immersive mode + landscape before loadContent
    // (pattern based on the working implementation from the pipboy/openharmony project).
    this.configureMainWindow(windowStage)
      .then(() => {
        this.loadMainContent(windowStage);
      });
  }

  /** Applies landscape orientation and hides the system bars on the main window. */
  private async configureMainWindow(windowStage: window.WindowStage): Promise<void> {
    const hiddenSystemBars: Array<'status' | 'navigation'> = [];
    let mainWindow: window.Window;

    try {
      mainWindow = windowStage.getMainWindowSync();
    } catch (err) {
      hilog.error(DOMAIN, 'Doom4OH', 'Failed to get the main window. Cause: %{public}s', JSON.stringify(err));
      return;
    }

    try {
      await mainWindow.setPreferredOrientation(window.Orientation.LANDSCAPE);
    } catch (err) {
      hilog.error(DOMAIN, 'Doom4OH', 'Failed to set landscape orientation. Cause: %{public}s', JSON.stringify(err));
    }

    try {
      await mainWindow.setWindowSystemBarEnable(hiddenSystemBars);
    } catch (err) {
      hilog.error(DOMAIN, 'Doom4OH', 'Failed to hide system bars. Cause: %{public}s', JSON.stringify(err));
    }

    try {
      await mainWindow.setSpecificSystemBarEnabled('navigationIndicator', false, false);
    } catch (err) {
      hilog.error(DOMAIN, 'Doom4OH', 'Failed to hide navigation indicator. Cause: %{public}s', JSON.stringify(err));
    }
  }

  /** Loads the game page (pages/Index) into the window stage. */
  private loadMainContent(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'Doom4OH', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'Doom4OH', 'Succeeded in loading the content.');
    });
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, 'Doom4OH', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    hilog.info(DOMAIN, 'Doom4OH', '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    hilog.info(DOMAIN, 'Doom4OH', '%{public}s', 'Ability onBackground');
  }
}
