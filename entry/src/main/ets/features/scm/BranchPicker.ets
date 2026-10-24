import { UiConst } from '../../components/UiConst';
import { ORIGIN, ScmModel } from './ScmModel';

/** Branch list (local + remote) with "create new branch". Shown as an overlay. */
@ComponentV2
export struct BranchPicker {
  @Param @Require model: ScmModel;
  @Event onClose: () => void = () => {
  };

  @Builder
  item(icon: Resource, label: string, detail: ResourceStr, onTap: () => void) {
    Row({ space: $r('app.float.space_s') }) {
      Image(icon)
        .width($r('app.float.icon_size_small'))
        .height($r('app.float.icon_size_small'))
        .fillColor($r('app.color.icon'))
      Text(label)
        .fontSize($r('app.float.font_m'))
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(UiConst.LAYOUT_WEIGHT_FILL)
        .maxLines(UiConst.MAX_LINES_TITLE)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(detail)
        .fontSize($r('app.float.font_xs'))
        .fontColor($r('app.color.text_muted'))
    }
    .width(UiConst.FULL)
    .height($r('app.float.list_row_touch'))
    .padding({ left: $r('app.float.space_m'), right: $r('app.float.space_m') })
    .onClick(onTap)
  }

  build() {
    Column() {
      Text($r('app.string.scm_switch_branch'))
        .fontSize($r('app.float.font_m'))
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width(UiConst.FULL)
        .padding($r('app.float.space_m'))
      List() {
        ListItem() {
          this.item($r('app.media.ic_add'), '', $r('app.string.scm_new_branch'), () => {
            this.onClose();
            this.model.createBranch();
          })
        }
        ForEach(this.model.branches.local, (b: string) => {
          ListItem() {
            this.item(b === this.model.branch ? $r('app.media.ic_check') : $r('app.media.ic_git_branch'), b,
              b === this.model.branch ? $r('app.string.scm_current') : '', () => {
                this.onClose();
                this.model.checkout(b);
              })
          }
        }, (b: string) => 'L' + b)
        ForEach(this.model.branches.remote, (b: string) => {
          ListItem() {
            this.item($r('app.media.ic_cloud'), ORIGIN + '/' + b, $r('app.string.scm_remote_branch'), () => {
              this.onClose();
              this.model.checkout(b);
            })
          }
        }, (b: string) => 'R' + b)
      }
      .layoutWeight(UiConst.LAYOUT_WEIGHT_FILL)
    }
    .width($r('app.float.quick_open_width'))
    .constraintSize({ maxWidth: UiConst.FLOATING_MAX_WIDTH, maxHeight: $r('app.float.popup_max_height') })
    .backgroundColor($r('app.color.dialog_bg'))
    .borderRadius($r('app.float.radius_l'))
    .border({ width: $r('app.float.border_width'), color: $r('app.color.border') })
    .shadow(ShadowStyle.OUTER_DEFAULT_MD)
  }
}
