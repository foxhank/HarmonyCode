import { InputModifier, TextAreaModifier } from '../../components/Modifiers';
import { UiConst } from '../../components/UiConst';

/** A titled group of settings with an optional hint below the title. */
@ComponentV2
export struct SettingsGroup {
  @Param title: ResourceStr = '';
  @Param hint: ResourceStr = '';
  @BuilderParam content: () => void = noContent;

  build() {
    Column({ space: $r('app.float.space_m') }) {
      if (this.title !== '') {
        Text(this.title)
          .fontSize($r('app.float.font_l'))
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .width(UiConst.FULL)
      }
      if (this.hint !== '') {
        Text(this.hint)
          .fontSize($r('app.float.font_xs'))
          .fontColor($r('app.color.text_muted'))
          .width(UiConst.FULL)
      }
      this.content()
    }
    .width(UiConst.FULL)
  }
}

/** Label with a switch. */
@ComponentV2
export struct ToggleRow {
  @Param @Require label: ResourceStr;
  @Param hint: ResourceStr = '';
  @Param @Require isOn: boolean;
  @Event onToggle: (on: boolean) => void = () => {
  };

  build() {
    Row({ space: $r('app.float.space_m') }) {
      Column({ space: $r('app.float.space_xxs') }) {
        Text(this.label)
          .fontSize($r('app.float.font_m'))
          .fontColor($r('app.color.text_primary'))
          .width(UiConst.FULL)
        if (this.hint !== '') {
          Text(this.hint)
            .fontSize($r('app.float.font_xs'))
            .fontColor($r('app.color.text_muted'))
            .width(UiConst.FULL)
        }
      }
      .layoutWeight(UiConst.LAYOUT_WEIGHT_FILL)
      Toggle({ type: ToggleType.Switch, isOn: this.isOn })
        .selectedColor($r('app.color.accent'))
        .onChange((on: boolean) => this.onToggle(on))
    }
    .width(UiConst.FULL)
  }
}

/** Label above a single-line text field. */
@ComponentV2
export struct TextFieldRow {
  @Param @Require label: ResourceStr;
  @Param @Require value: string;
  @Param placeholder: ResourceStr = '';
  @Param hint: ResourceStr = '';
  @Param inputType: InputType = InputType.Normal;
  @Event onChanged: (v: string) => void = () => {
  };
  private inputStyle: InputModifier = new InputModifier();

  build() {
    Column({ space: $r('app.float.space_xs') }) {
      Text(this.label)
        .fontSize($r('app.float.font_s'))
        .fontColor($r('app.color.text_secondary'))
        .width(UiConst.FULL)
      TextInput({ text: this.value, placeholder: this.placeholder })
        .attributeModifier(this.inputStyle)
        .type(this.inputType)
        .width(UiConst.FULL)
        .onChange((v: string) => this.onChanged(v))
      if (this.hint !== '') {
        Text(this.hint)
          .fontSize($r('app.float.font_xs'))
          .fontColor($r('app.color.text_muted'))
          .width(UiConst.FULL)
      }
    }
    .width(UiConst.FULL)
  }
}

/** Label above a multi-line text field. */
@ComponentV2
export struct TextAreaRow {
  @Param @Require label: ResourceStr;
  @Param @Require value: string;
  @Param placeholder: ResourceStr = '';
  @Param hint: ResourceStr = '';
  @Event onChanged: (v: string) => void = () => {
  };
  private areaStyle: TextAreaModifier = new TextAreaModifier();

  build() {
    Column({ space: $r('app.float.space_xs') }) {
      Text(this.label)
        .fontSize($r('app.float.font_s'))
        .fontColor($r('app.color.text_secondary'))
        .width(UiConst.FULL)
      TextArea({ text: this.value, placeholder: this.placeholder })
        .attributeModifier(this.areaStyle)
        .width(UiConst.FULL)
        .constraintSize({ minHeight: $r('app.float.commit_box_min_height') })
        .onChange((v: string) => this.onChanged(v))
      if (this.hint !== '') {
        Text(this.hint)
          .fontSize($r('app.float.font_xs'))
          .fontColor($r('app.color.text_muted'))
          .width(UiConst.FULL)
      }
    }
    .width(UiConst.FULL)
  }
}

/** A tappable row that leads to a deeper settings page. */
@ComponentV2
export struct NavRow {
  @Param icon: Resource | undefined = undefined;
  @Param @Require title: ResourceStr;
  @Param subtitle: ResourceStr = '';
  @Param selected: boolean = false;
  @Param touch: boolean = false;
  @Event onTap: () => void = () => {
  };

  build() {
    Row({ space: $r('app.float.space_m') }) {
      if (this.icon !== undefined) {
        Image(this.icon)
          .width($r('app.float.icon_size'))
          .height($r('app.float.icon_size'))
          .fillColor(this.selected ? $r('app.color.accent') : $r('app.color.icon'))
      }
      Column({ space: $r('app.float.space_xxs') }) {
        Text(this.title)
          .fontSize($r('app.float.font_m'))
          .fontWeight(this.selected ? FontWeight.Medium : FontWeight.Normal)
          .fontColor($r('app.color.text_primary'))
          .width(UiConst.FULL)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.subtitle !== '') {
          Text(this.subtitle)
            .fontSize($r('app.float.font_xs'))
            .fontColor($r('app.color.text_muted'))
            .width(UiConst.FULL)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .layoutWeight(UiConst.LAYOUT_WEIGHT_FILL)
      Image($r('app.media.ic_chevron_right'))
        .width($r('app.float.icon_size_small'))
        .height($r('app.float.icon_size_small'))
        .fillColor($r('app.color.icon_muted'))
    }
    .width(UiConst.FULL)
    .constraintSize({ minHeight: this.touch ? $r('app.float.list_row_touch_tall') : $r('app.float.list_row_tall') })
    .padding({ left: $r('app.float.space_m'), right: $r('app.float.space_m') })
    .backgroundColor(this.selected ? $r('app.color.selected_bg') : Color.Transparent)
    .borderRadius($r('app.float.radius_m'))
    .onClick(() => this.onTap())
  }
}

@Builder
function noContent() {
}
