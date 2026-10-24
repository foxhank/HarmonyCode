import { UiConst } from '../../components/UiConst';
import { ToastKind, ToastModel } from './ToastModel';

/** Shows the current toast at the bottom of the window. */
@ComponentV2
export struct ToastHost {
  @Param @Require model: ToastModel;

  build() {
    if (this.model.message.length > 0) {
      Column() {
        Blank()
        Text(this.model.message)
          .fontSize($r('app.float.font_m'))
          .fontColor($r('app.color.toast_text'))
          .backgroundColor(this.model.kind === ToastKind.ERROR ? $r('app.color.toast_error_bg') : $r('app.color.toast_bg'))
          .padding({
            left: $r('app.float.space_l'), right: $r('app.float.space_l'),
            top: $r('app.float.space_s'), bottom: $r('app.float.space_s')
          })
          .borderRadius($r('app.float.radius_l'))
          .constraintSize({ maxWidth: UiConst.FLOATING_MAX_WIDTH })
          .maxLines(UiConst.MAX_LINES_BODY)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .shadow(ShadowStyle.OUTER_DEFAULT_SM)
          .onClick(() => this.model.dismiss())
          .margin({ bottom: $r('app.float.toast_bottom_margin') })
      }
      .width(UiConst.FULL)
      .height(UiConst.FULL)
      .hitTestBehavior(HitTestMode.Transparent)
      .zIndex(UiConst.Z_TOAST)
    }
  }
}
