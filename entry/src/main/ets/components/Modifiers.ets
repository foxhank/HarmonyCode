/** Shared text-field look (works for TextInput). */
export class InputModifier implements AttributeModifier<TextInputAttribute> {
  applyNormalAttribute(instance: TextInputAttribute): void {
    instance
      .height($r('app.float.input_height'))
      .fontSize($r('app.float.font_m'))
      .fontColor($r('app.color.text_primary'))
      .placeholderColor($r('app.color.text_muted'))
      .backgroundColor($r('app.color.input_bg'))
      .borderRadius($r('app.float.radius_s'))
      .border({ width: $r('app.float.border_width'), color: $r('app.color.input_border') })
      .caretColor($r('app.color.accent'))
      .padding({ left: $r('app.float.space_s'), right: $r('app.float.space_s') });
  }

  applyFocusedAttribute(instance: TextInputAttribute): void {
    instance.border({ width: $r('app.float.border_width'), color: $r('app.color.border_focus') });
  }
}

/** Shared multi-line field look. */
export class TextAreaModifier implements AttributeModifier<TextAreaAttribute> {
  applyNormalAttribute(instance: TextAreaAttribute): void {
    instance
      .fontSize($r('app.float.font_m'))
      .fontColor($r('app.color.text_primary'))
      .placeholderColor($r('app.color.text_muted'))
      .backgroundColor($r('app.color.input_bg'))
      .borderRadius($r('app.float.radius_s'))
      .border({ width: $r('app.float.border_width'), color: $r('app.color.input_border') })
      .caretColor($r('app.color.accent'));
  }

  applyFocusedAttribute(instance: TextAreaAttribute): void {
    instance.border({ width: $r('app.float.border_width'), color: $r('app.color.border_focus') });
  }
}

/** Panel / card surface. */
export class CardModifier implements AttributeModifier<ColumnAttribute> {
  applyNormalAttribute(instance: ColumnAttribute): void {
    instance
      .backgroundColor($r('app.color.card_bg'))
      .borderRadius($r('app.float.radius_l'))
      .border({ width: $r('app.float.border_width'), color: $r('app.color.card_edge') })
      .shadow(ShadowStyle.OUTER_DEFAULT_SM);
  }
}
