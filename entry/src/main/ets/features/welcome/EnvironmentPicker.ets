import { EnvironmentDef } from '../../core/project/Catalog';
import { UiConst } from '../../components/UiConst';
import { CatalogText } from '../app/CatalogText';

/** Radio-style list of environments ("interpreters" in PyCharm terms). */
@ComponentV2
export struct EnvironmentPicker {
  @Param @Require environments: EnvironmentDef[];
  @Param @Require selectedId: string;
  @Event onSelect: (env: EnvironmentDef) => void = () => {
  };

  @Builder
  tag(text: ResourceStr, color: ResourceColor) {
    Text(text)
      .fontSize($r('app.float.font_xs'))
      .fontColor(color)
      .padding({ left: $r('app.float.space_xs'), right: $r('app.float.space_xs') })
      .border({ width: $r('app.float.border_width'), color: color, radius: $r('app.float.radius_s') })
  }

  build() {
    Column({ space: $r('app.float.space_s') }) {
      ForEach(this.environments, (env: EnvironmentDef) => {
        Row({ space: $r('app.float.space_m') }) {
          Radio({ value: env.id, group: 'environment' })
            .checked(env.id === this.selectedId)
            .onChange((checked: boolean) => {
              if (checked) {
                this.onSelect(env);
              }
            })
          Column({ space: $r('app.float.space_xxs') }) {
            Row({ space: $r('app.float.space_s') }) {
              Text(CatalogText.envName(env.id))
                .fontSize($r('app.float.font_m'))
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))
              if (env.recommended) {
                this.tag($r('app.string.badge_recommended'), $r('app.color.accent'))
              }
            }
            Text(CatalogText.envDetail(env.id))
              .fontSize($r('app.float.font_s'))
              .fontColor($r('app.color.text_secondary'))
            if (CatalogText.envStatus(env).length > 0) {
              Text(CatalogText.envStatus(env))
                .fontSize($r('app.float.font_xs'))
                .fontColor($r('app.color.text_muted'))
            }
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(UiConst.LAYOUT_WEIGHT_FILL)
        }
        .width(UiConst.FULL)
        .padding($r('app.float.space_m'))
        .borderRadius($r('app.float.radius_m'))
        .border({
          width: $r('app.float.border_width'),
          color: env.id === this.selectedId ? $r('app.color.border_focus') : $r('app.color.border')
        })
        .backgroundColor(env.id === this.selectedId ? $r('app.color.selected_bg') : $r('app.color.card_bg'))
        .onClick(() => this.onSelect(env))
      }, (env: EnvironmentDef) => env.id)
    }
    .width(UiConst.FULL)
  }
}
