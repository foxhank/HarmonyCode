import { Keys } from '../../core/terminal/Keys';
import { UiConst } from '../../components/UiConst';
import { TerminalController } from './TerminalController';

interface KeyDef {
  label: ResourceStr;
  seq: string;
}

/** Keys missing from on-screen keyboards (Esc, Tab, Ctrl, arrows...). Shown on phones and tablets. */
@ComponentV2
export struct ExtraKeys {
  @Param @Require model: TerminalController;

  private keys(): KeyDef[] {
    return [
      { label: $r('app.string.key_esc'), seq: Keys.ESC },
      { label: $r('app.string.key_tab'), seq: Keys.TAB },
      { label: $r('app.string.key_home'), seq: Keys.HOME },
      { label: $r('app.string.key_end'), seq: Keys.END },
      { label: $r('app.string.key_up'), seq: Keys.UP },
      { label: $r('app.string.key_down'), seq: Keys.DOWN },
      { label: $r('app.string.key_left'), seq: Keys.LEFT },
      { label: $r('app.string.key_right'), seq: Keys.RIGHT },
      { label: '|', seq: '|' },
      { label: '/', seq: '/' },
      { label: '-', seq: '-' },
      { label: '~', seq: '~' },
    ];
  }

  @Builder
  keyCap(label: ResourceStr, active: boolean, onTap: () => void) {
    Text(label)
      .fontSize($r('app.float.font_s'))
      .fontColor(active ? $r('app.color.text_on_accent') : $r('app.color.text_primary'))
      .backgroundColor(active ? $r('app.color.accent') : $r('app.color.keycap_bg'))
      .borderRadius($r('app.float.radius_s'))
      .textAlign(TextAlign.Center)
      .constraintSize({ minWidth: $r('app.float.extra_key_min_width') })
      .height($r('app.float.extra_key_height'))
      .padding({ left: $r('app.float.space_s'), right: $r('app.float.space_s') })
      .onClick(onTap)
  }

  build() {
    Scroll() {
      Row({ space: $r('app.float.space_xs') }) {
        this.keyCap($r('app.string.key_ctrl'), this.model.ctrlArmed, () => this.model.toggleCtrl())
        ForEach(this.keys(), (k: KeyDef) => {
          this.keyCap(k.label, false, () => this.model.sendKey(k.seq))
        }, (k: KeyDef) => k.seq)
      }
      .padding({ left: $r('app.float.space_s'), right: $r('app.float.space_s') })
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width(UiConst.FULL)
    .height($r('app.float.extra_keys_bar_height'))
    .backgroundColor($r('app.color.panel_bg'))
    .border({ width: { top: $r('app.float.border_width') }, color: $r('app.color.border') })
  }
}
