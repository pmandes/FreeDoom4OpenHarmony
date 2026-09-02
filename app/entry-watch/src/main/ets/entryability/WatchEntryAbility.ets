import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
const DOMAIN = 0x0000;

/** Main UIAbility: configures the immersive round-screen window and loads the game page. */
export default class WatchEntryAbility extends UIAbility {
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
    // (pattern from the working pipboy/openharmony implementation).
    this.configureMainWindow(windowStage)
      .then(() => {
        this.loadMainContent(windowStage);
      });
  }

  /** Hides the system bars and disables the back gesture before content loads. */
  private async configureMainWindow(windowStage: window.WindowStage): Promise<void> {
    const hiddenSystemBars: Array<'status' | 'navigation'> = [];
    let mainWindow: window.Window;

    try {
      mainWindow = windowStage.getMainWindowSync();
    } catch (err) {
      hilog.error(DOMAIN, 'Doom4OH', 'Failed to get the main window. Cause: %{public}s', JSON.stringify(err));
      return;
    }

    // Watch: no orientation lock - the round screen has a fixed layout.
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

    // Disable the system back gesture - an accidental swipe (e.g. while strafing
    // with the joystick) must not exit the game. Exit via the watch side button.
    try {
      await mainWindow.setGestureBackEnabled(false);
    } catch (err) {
      hilog.error(DOMAIN, 'Doom4OH', 'Failed to disable back gesture. Cause: %{public}s', JSON.stringify(err));
    }
  }

  /** Loads the Index page into the window stage. */
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
