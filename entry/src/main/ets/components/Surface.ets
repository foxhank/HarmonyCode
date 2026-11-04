import { UiConst } from './UiConst';

/**
 * HarmonyOS-style surfaces: content floats on soft, layered shadows instead of hard borders,
 * and bars use frosted glass over the content behind them.
 */

/** A raised card: rounded, softly shadowed, with a hairline edge that catches light. */
export class ElevatedCardModifier implements AttributeModifier<ColumnAttribute> {
  applyNormalAttribute(instance: ColumnAttribute): void {
    instance
      .backgroundColor($r('app.color.card_bg'))
      .borderRadius($r('app.float.radius_l'))
      .border({ width: $r('app.float.border_width'), color: $r('app.color.card_edge') })
      .shadow(ShadowStyle.OUTER_DEFAULT_SM);
  }

  applyPressedAttribute(instance: ColumnAttribute): void {
    instance.shadow(ShadowStyle.OUTER_DEFAULT_XS);
  }
}

/** Frosted glass for bars that float over content (bottom navigation, composer, headers). */
export class GlassBarModifier implements AttributeModifier<RowAttribute> {
  applyNormalAttribute(instance: RowAttribute): void {
    instance
      .backgroundColor($r('app.color.glass_bg'))
      .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
      .border({ width: { top: $r('app.float.border_width') }, color: $r('app.color.card_edge') });
  }
}

/** Glass for a floating column (the agent composer). */
export class GlassPanelModifier implements AttributeModifier<ColumnAttribute> {
  applyNormalAttribute(instance: ColumnAttribute): void {
    instance
      .backgroundColor($r('app.color.glass_bg'))
      .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
      .borderRadius($r('app.float.radius_xl'))
      .border({ width: $r('app.float.border_width'), color: $r('app.color.card_edge') })
      .shadow(ShadowStyle.OUTER_DEFAULT_MD);
  }
}

/** Connection state as a small dot with a soft glow in its own color. */
@ComponentV2
export struct StatusDot {
  @Param @Require color: ResourceColor;
  @Param glow: boolean = true;

  build() {
    Circle()
      .width($r('app.float.status_dot_size'))
      .height($r('app.float.status_dot_size'))
      .fill(this.color)
      .shadow(this.glow ? { radius: UiConst.GLOW_RADIUS, color: this.color, offsetX: 0, offsetY: 0 } :
        { radius: 0, color: Color.Transparent })
  }
}

/** An icon on a tinted rounded tile, the way HarmonyOS lists lead with icons. */
@ComponentV2
export struct IconTile {
  @Param @Require icon: Resource;
  @Param tint: ResourceColor = $r('app.color.accent');
  @Param tileBg: ResourceColor = $r('app.color.accent_soft');

  build() {
    Stack() {
      Image(this.icon)
        .width($r('app.float.icon_size'))
        .height($r('app.float.icon_size'))
        .fillColor(this.tint)
    }
    .width($r('app.float.icon_tile_size'))
    .height($r('app.float.icon_tile_size'))
    .backgroundColor(this.tileBg)
    .borderRadius($r('app.float.radius_m'))
  }
}
