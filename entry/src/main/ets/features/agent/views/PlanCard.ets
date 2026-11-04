import { PlanStep, StepStatus } from '../../../core/agent/PlanTypes';
import { UiConst } from '../../../components/UiConst';

/** The agent's current task plan, collapsible. */
@ComponentV2
export struct PlanCard {
  @Param @Require steps: PlanStep[];
  @Local expanded: boolean = true;

  private done(): number {
    return this.steps.filter((s: PlanStep) => s.status === StepStatus.COMPLETED).length;
  }

  @Builder
  marker(status: string) {
    if (status === StepStatus.COMPLETED) {
      Image($r('app.media.ic_check'))
        .width($r('app.float.icon_size_small'))
        .height($r('app.float.icon_size_small'))
        .fillColor($r('app.color.git_added'))
    } else if (status === StepStatus.IN_PROGRESS) {
      LoadingProgress()
        .width($r('app.float.icon_size_small'))
        .height($r('app.float.icon_size_small'))
        .color($r('app.color.accent'))
    } else {
      Circle()
        .width($r('app.float.plan_dot_size'))
        .height($r('app.float.plan_dot_size'))
        .fillOpacity(0)
        .stroke($r('app.color.icon_muted'))
        .strokeWidth(1)
        .margin({ left: $r('app.float.space_xxs'), right: $r('app.float.space_xxs') })
    }
  }

  build() {
    Column({ space: $r('app.float.space_xs') }) {
      Row({ space: $r('app.float.space_s') }) {
        Text($r('app.string.agent_plan_title'))
          .fontSize($r('app.float.font_s'))
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        Text(this.done() + '/' + this.steps.length)
          .fontSize($r('app.float.font_xs'))
          .fontColor($r('app.color.text_muted'))
          .layoutWeight(UiConst.LAYOUT_WEIGHT_FILL)
        Image(this.expanded ? $r('app.media.ic_chevron_down') : $r('app.media.ic_chevron_right'))
          .width($r('app.float.icon_size_small'))
          .height($r('app.float.icon_size_small'))
          .fillColor($r('app.color.icon'))
      }
      .width(UiConst.FULL)
      .onClick(() => {
        this.expanded = !this.expanded;
      })
      if (this.expanded) {
        ForEach(this.steps, (s: PlanStep) => {
          Row({ space: $r('app.float.space_s') }) {
            this.marker(s.status)
            Text(s.step)
              .fontSize($r('app.float.font_s'))
              .fontColor(s.status === StepStatus.COMPLETED ? $r('app.color.text_muted') : $r('app.color.text_primary'))
              .decoration({ type: s.status === StepStatus.COMPLETED ? TextDecorationType.LineThrough : TextDecorationType.None })
              .layoutWeight(UiConst.LAYOUT_WEIGHT_FILL)
          }
          .width(UiConst.FULL)
          .alignItems(VerticalAlign.Top)
        }, (s: PlanStep, i: number) => i + ':' + s.status + ':' + s.step)
      }
    }
    .width(UiConst.FULL)
    .padding($r('app.float.space_m'))
    .backgroundColor($r('app.color.card_bg'))
    .borderRadius($r('app.float.radius_l'))
    .border({ width: $r('app.float.border_width'), color: $r('app.color.card_edge') })
    .shadow(ShadowStyle.OUTER_DEFAULT_SM)
  }
}
