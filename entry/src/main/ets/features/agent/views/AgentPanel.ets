import { Strings } from '../../../core/common/Strings';
import { ModelChoice } from '../../../core/settings/AgentSettingsStore';
import { IconButton } from '../../../components/IconButton';
import { TextAreaModifier } from '../../../components/Modifiers';
import { GlassPanelModifier } from '../../../components/Surface';
import { UiConst } from '../../../components/UiConst';
import { AgentModel } from '../AgentModel';
import { ItemKind, TranscriptItem } from '../TranscriptItem';
import { MarkdownView } from './MarkdownView';
import { PlanCard } from './PlanCard';
import { ToolCallCard } from './ToolCallCard';

const KEY_ENTER: number = 2054;
const PERCENT: number = 100;

/** The coding agent: transcript, plan, model picker and composer. */
@ComponentV2
export struct AgentPanel {
  @Param @Require model: AgentModel;
  @Param touch: boolean = false;
  /** Shows a close button (docked panel / overlay). */
  @Param closable: boolean = false;
  @Event onClose: () => void = () => {
  };
  private scroller: Scroller = new Scroller();
  private areaStyle: TextAreaModifier = new TextAreaModifier();
  private glass: GlassPanelModifier = new GlassPanelModifier();

  @Monitor('model.revision')
  onRevision(): void {
    // Keep the newest output in view while the agent works.
    setTimeout(() => {
      this.scroller.scrollEdge(Edge.Bottom);
    }, 0);
  }

  private buttonSize(): Resource {
    return this.touch ? $r('app.float.icon_button_size_touch') : $r('app.float.icon_button_size');
  }

  private contextPercent(): number {
    if (this.model.contextWindow <= 0) {
      return 0;
    }
    return Math.min(PERCENT, Math.round(this.model.contextUsed * PERCENT / this.model.contextWindow));
  }

  @Builder
  modelMenu() {
    Menu() {
      ForEach(this.model.settings.choices(), (c: ModelChoice) => {
        MenuItem({ content: c.label })
          .selected(c.providerId === this.model.settings.providerId && c.modelId === this.model.settings.modelId)
          .onClick(() => this.model.selectModel(c.providerId, c.modelId))
      }, (c: ModelChoice) => c.providerId + '/' + c.modelId)
      MenuItem({ content: $r('app.string.agent_manage_models') })
        .onClick(() => this.model.openSettings())
    }
  }

  @Builder
  header() {
    Row({ space: $r('app.float.space_xs') }) {
      Image($r('app.media.ic_agent'))
        .width($r('app.float.icon_size'))
        .height($r('app.float.icon_size'))
        .fillColor($r('app.color.accent'))
        .margin({ left: $r('app.float.space_s') })
      Text($r('app.string.agent_title'))
        .fontSize($r('app.float.font_m'))
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
      Blank()
      if (this.model.contextWindow > 0 && this.model.contextUsed > 0) {
        Text(this.contextPercent() + '%')
          .fontSize($r('app.float.font_xxs'))
          .fontColor($r('app.color.text_muted'))
          .accessibilityText(Strings.get('agent_context_used', this.contextPercent()))
      }
      IconButton({
        icon: $r('app.media.ic_add'), label: $r('app.string.agent_new_chat'), buttonSize: this.buttonSize(),
        isEnabled: !this.model.busy, onTap: () => this.model.newChat()
      })
      IconButton({
        icon: $r('app.media.ic_settings'), label: $r('app.string.agent_settings'), buttonSize: this.buttonSize(),
        onTap: () => this.model.openSettings()
      })
      if (this.closable) {
        IconButton({
          icon: $r('app.media.ic_close'), label: $r('app.string.action_close'), buttonSize: this.buttonSize(),
          onTap: () => this.onClose()
        })
      }
    }
    .width(UiConst.FULL)
    .height(this.touch ? $r('app.float.titlebar_height_touch') : $r('app.float.titlebar_height'))
    .padding({ right: $r('app.float.space_xs') })
  }

  @Builder
  emptyState() {
    Column({ space: $r('app.float.space_m') }) {
      Stack() {
        Image($r('app.media.ic_agent'))
          .width($r('app.float.icon_size_large'))
          .height($r('app.float.icon_size_large'))
          .fillColor($r('app.color.text_on_bubble'))
      }
      .width($r('app.float.empty_icon_size'))
      .height($r('app.float.empty_icon_size'))
      .borderRadius($r('app.float.radius_l'))
      .linearGradient({ angle: UiConst.GRADIENT_ANGLE,
        colors: [[$r('app.color.bubble_start'), 0], [$r('app.color.bubble_end'), 1]] })
      .shadow({ radius: UiConst.SHADOW_SOFT_RADIUS, color: $r('app.color.bubble_shadow'),
        offsetY: UiConst.SHADOW_SOFT_OFFSET })
      Text(this.model.hasModel ? $r('app.string.agent_empty_title') : $r('app.string.agent_setup_title'))
        .fontSize($r('app.float.font_l'))
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .textAlign(TextAlign.Center)
      Text(this.model.hasModel ? $r('app.string.agent_empty_message') : $r('app.string.agent_setup_message'))
        .fontSize($r('app.float.font_s'))
        .fontColor($r('app.color.text_secondary'))
        .textAlign(TextAlign.Center)
      if (!this.model.hasModel) {
        Button($r('app.string.agent_setup_action'))
          .fontSize($r('app.float.font_s'))
          .height($r('app.float.button_height'))
          .backgroundColor($r('app.color.button_primary_bg'))
          .fontColor($r('app.color.text_on_accent'))
          .borderRadius($r('app.float.radius_s'))
          .onClick(() => this.model.openSettings())
      }
    }
    .width(UiConst.FULL)
    .padding($r('app.float.space_xl'))
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  item(it: TranscriptItem) {
    if (it.kind === ItemKind.USER) {
      Column({ space: $r('app.float.space_xxs') }) {
        Text(it.text)
          .fontSize($r('app.float.font_m'))
          .fontColor($r('app.color.text_on_bubble'))
          .copyOption(CopyOptions.LocalDevice)
          .padding({ left: $r('app.float.space_m'), right: $r('app.float.space_m'), top: $r('app.float.space_s'),
            bottom: $r('app.float.space_s') })
          .linearGradient({ angle: UiConst.GRADIENT_ANGLE,
            colors: [[$r('app.color.bubble_start'), 0], [$r('app.color.bubble_end'), 1]] })
          .borderRadius({ topLeft: $r('app.float.radius_xl'), topRight: $r('app.float.radius_xl'),
            bottomLeft: $r('app.float.radius_xl'), bottomRight: $r('app.float.radius_xs') })
          .shadow({ radius: UiConst.SHADOW_SOFT_RADIUS, color: $r('app.color.bubble_shadow'),
            offsetY: UiConst.SHADOW_SOFT_OFFSET })
          .constraintSize({ maxWidth: UiConst.AGENT_USER_MAX_WIDTH })
        if (it.queued) {
          Text($r('app.string.agent_queued'))
            .fontSize($r('app.float.font_xxs'))
            .fontColor($r('app.color.text_muted'))
        }
      }
      .width(UiConst.FULL)
      .alignItems(HorizontalAlign.End)
    } else if (it.kind === ItemKind.ASSISTANT) {
      MarkdownView({ text: it.text })
    } else if (it.kind === ItemKind.REASONING) {
      Column({ space: $r('app.float.space_xs') }) {
        Row({ space: $r('app.float.space_xs') }) {
          Text(it.streaming ? $r('app.string.agent_thinking') : $r('app.string.agent_thought'))
            .fontSize($r('app.float.font_xs'))
            .fontColor($r('app.color.text_muted'))
          Image(it.expanded ? $r('app.media.ic_chevron_down') : $r('app.media.ic_chevron_right'))
            .width($r('app.float.icon_size_small'))
            .height($r('app.float.icon_size_small'))
            .fillColor($r('app.color.icon_muted'))
        }
        .onClick(() => {
          it.expanded = !it.expanded;
        })
        if (it.expanded) {
          Text(it.text)
            .fontSize($r('app.float.font_xs'))
            .fontColor($r('app.color.text_muted'))
            .fontStyle(FontStyle.Italic)
            .width(UiConst.FULL)
        }
      }
      .width(UiConst.FULL)
      .alignItems(HorizontalAlign.Start)
    } else if (it.kind === ItemKind.TOOL) {
      ToolCallCard({
        item: it, touch: this.touch,
        onAnswer: (decision: string, feedback: string) => this.model.answer(it, decision, feedback),
        onOpenFile: (target: string) => this.model.openFile(target),
        onReply: (answer: string) => this.model.reply(it, answer)
      })
    } else if (it.kind === ItemKind.NOTICE) {
      Text(Strings.get(it.text))
        .fontSize($r('app.float.font_xs'))
        .fontColor($r('app.color.text_muted'))
        .width(UiConst.FULL)
        .textAlign(TextAlign.Center)
    } else {
      Row({ space: $r('app.float.space_s') }) {
        Image($r('app.media.ic_close'))
          .width($r('app.float.icon_size_small'))
          .height($r('app.float.icon_size_small'))
          .fillColor($r('app.color.danger'))
        Text(it.text)
          .fontSize($r('app.float.font_s'))
          .fontColor($r('app.color.danger'))
          .copyOption(CopyOptions.LocalDevice)
          .layoutWeight(UiConst.LAYOUT_WEIGHT_FILL)
      }
      .width(UiConst.FULL)
      .alignItems(VerticalAlign.Top)
      .padding($r('app.float.space_s'))
      .backgroundColor($r('app.color.agent_error_bg'))
      .borderRadius($r('app.float.radius_m'))
    }
  }

  @Builder
  transcript() {
    List({ scroller: this.scroller, space: UiConst.AGENT_ITEM_GAP }) {
      ForEach(this.model.items, (it: TranscriptItem) => {
        ListItem() {
          this.item(it)
        }
      }, (it: TranscriptItem) => it.id.toString())
      if (this.model.busy) {
        ListItem() {
          Row({ space: $r('app.float.space_s') }) {
            LoadingProgress()
              .width($r('app.float.icon_size_small'))
              .height($r('app.float.icon_size_small'))
              .color($r('app.color.accent'))
            Text($r('app.string.agent_working'))
              .fontSize($r('app.float.font_xs'))
              .fontColor($r('app.color.text_muted'))
          }
        }
      }
    }
    .width(UiConst.FULL)
    .layoutWeight(UiConst.LAYOUT_WEIGHT_FILL)
    .padding({ left: $r('app.float.space_m'), right: $r('app.float.space_m'), top: $r('app.float.space_m') })
    .scrollBar(BarState.Auto)
    .edgeEffect(EdgeEffect.Spring)
  }

  @Builder
  composer() {
    Column({ space: $r('app.float.space_xs') }) {
      TextArea({
        text: this.model.draft,
        placeholder: this.model.busy ? $r('app.string.agent_placeholder_busy') : $r('app.string.agent_placeholder')
      })
        .attributeModifier(this.areaStyle)
        .width(UiConst.FULL)
        .constraintSize({ minHeight: $r('app.float.agent_input_min_height'), maxHeight: $r('app.float.agent_input_max_height') })
        .onChange((v: string) => {
          this.model.draft = v;
        })
        .onKeyPreIme((e: KeyEvent) => {
          // Enter sends; Shift+Enter inserts a new line (hardware keyboards).
          if (e.type === KeyType.Down && e.keyCode === KEY_ENTER && e.getModifierKeyState?.(['Shift']) !== true) {
            this.model.send();
            return true;
          }
          return false;
        })
      Row({ space: $r('app.float.space_xs') }) {
        Row({ space: $r('app.float.space_xxs') }) {
          Text(this.model.hasModel ? this.model.modelName() : Strings.get('agent_no_model'))
            .fontSize($r('app.float.font_xs'))
            .fontColor($r('app.color.text_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Image($r('app.media.ic_chevron_down'))
            .width($r('app.float.icon_size_small'))
            .height($r('app.float.icon_size_small'))
            .fillColor($r('app.color.icon'))
        }
        .height(this.buttonSize())
        .padding({ left: $r('app.float.space_xs'), right: $r('app.float.space_xs') })
        .borderRadius($r('app.float.radius_s'))
        .bindMenu(this.modelMenu())
        .accessibilityText($r('app.string.agent_choose_model'))
        Blank()
        if (this.model.busy) {
          IconButton({
            icon: $r('app.media.ic_stop'), label: $r('app.string.agent_stop'), buttonSize: this.buttonSize(),
            color: $r('app.color.danger'), onTap: () => this.model.stop()
          })
        }
        IconButton({
          icon: $r('app.media.ic_send'),
          label: this.model.busy ? $r('app.string.agent_send_while_busy') : $r('app.string.agent_send'),
          buttonSize: this.buttonSize(), color: $r('app.color.accent'), isEnabled: this.model.draft.trim().length > 0,
          onTap: () => this.model.send()
        })
      }
      .width(UiConst.FULL)
    }
    .attributeModifier(this.glass)
    .width(UiConst.FULL)
    .padding($r('app.float.space_s'))
    .margin({ left: $r('app.float.space_s'), right: $r('app.float.space_s'), bottom: $r('app.float.space_s') })
  }

  build() {
    Column() {
      this.header()
      if (this.model.items.length === 0) {
        Column() {
          this.emptyState()
        }
        .layoutWeight(UiConst.LAYOUT_WEIGHT_FILL)
        .justifyContent(FlexAlign.Center)
      } else {
        this.transcript()
      }
      if (this.model.plan.length > 0) {
        Column() {
          PlanCard({ steps: this.model.plan })
        }
        .padding({ left: $r('app.float.space_s'), right: $r('app.float.space_s'), top: $r('app.float.space_xs') })
      }
      this.composer()
    }
    .width(UiConst.FULL)
    .height(UiConst.FULL)
    .backgroundColor($r('app.color.app_bg'))
  }
}
