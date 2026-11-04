import { LengthMetrics } from '@kit.ArkUI';
import { ToolCallStatus } from '../../../core/agent/AgentEvents';
import { ApprovalDecision } from '../../../core/agent/Approval';
import { QuestionOption } from '../../../core/agent/Interaction';
import { ToolKind } from '../../../core/agent/ToolTypes';
import { Strings } from '../../../core/common/Strings';
import { MONO_FONT } from '../../../components/Fonts';
import { InputModifier } from '../../../components/Modifiers';
import { UiConst } from '../../../components/UiConst';
import { TranscriptItem } from '../TranscriptItem';
import { DiffView } from './DiffView';

const OUTPUT_PREVIEW_CHARS: number = 6000;

/** One tool call: status, what it acts on, expandable output, and approval controls. */
@ComponentV2
export struct ToolCallCard {
  @Param @Require item: TranscriptItem;
  @Param touch: boolean = false;
  @Event onAnswer: (decision: string, feedback: string) => void = () => {
  };
  @Event onOpenFile: (target: string) => void = () => {
  };
  /** Answer to an ask_user question ('' = dismissed). */
  @Event onReply: (answer: string) => void = () => {
  };
  @Local feedback: string = '';
  @Local picked: string[] = [];
  @Local freeText: string = '';
  private inputStyle: InputModifier = new InputModifier();

  private verb(): string {
    return Strings.get(this.item.verbKey);
  }

  private isFileTool(): boolean {
    return this.item.toolKind === ToolKind.EDIT || this.item.verbKey === 'agent_tool_read';
  }

  private detail(): string {
    if (this.item.running && this.item.live.length > 0) {
      return this.item.live;
    }
    const d = this.item.display.length > 0 ? this.item.display : this.item.output;
    return d.length > OUTPUT_PREVIEW_CHARS ? d.substring(0, OUTPUT_PREVIEW_CHARS) + '\n…' : d;
  }

  private isDiff(text: string): boolean {
    return text.startsWith('--- a/');
  }

  private alwaysLabel(): string {
    if (this.item.toolKind === ToolKind.EXECUTE) {
      return this.item.ruleKey.length > 0 ? Strings.get('agent_approve_always_prefix', this.item.ruleKey) :
        Strings.get('agent_approve_always_commands');
    }
    if (this.item.toolKind === ToolKind.NETWORK) {
      return Strings.get('agent_approve_always_web');
    }
    return Strings.get('agent_approve_always_edits');
  }

  private approvalTitle(): Resource {
    if (this.item.toolKind === ToolKind.EXECUTE) {
      return $r('app.string.agent_approve_command_title');
    }
    if (this.item.toolKind === ToolKind.NETWORK) {
      return $r('app.string.agent_approve_web_title');
    }
    return $r('app.string.agent_approve_edit_title');
  }

  private togglePick(label: string): void {
    if (!this.item.multiSelect) {
      this.onReply(label);
      return;
    }
    this.picked = this.picked.indexOf(label) >= 0 ? this.picked.filter((p: string) => p !== label) :
      this.picked.concat([label]);
  }

  private submitAnswer(): void {
    const parts = this.picked.slice();
    if (this.freeText.trim().length > 0) {
      parts.push(this.freeText.trim());
    }
    if (parts.length > 0) {
      this.onReply(parts.join('; '));
      this.picked = [];
      this.freeText = '';
    }
  }

  @Builder
  statusIcon() {
    if (this.item.running) {
      LoadingProgress()
        .width($r('app.float.icon_size_small'))
        .height($r('app.float.icon_size_small'))
        .color($r('app.color.accent'))
    } else if (this.item.awaitingApproval) {
      Image($r('app.media.ic_shield'))
        .width($r('app.float.icon_size_small'))
        .height($r('app.float.icon_size_small'))
        .fillColor($r('app.color.warning'))
    } else if (this.item.status === ToolCallStatus.DONE) {
      Image($r('app.media.ic_check'))
        .width($r('app.float.icon_size_small'))
        .height($r('app.float.icon_size_small'))
        .fillColor($r('app.color.git_added'))
    } else {
      Image($r('app.media.ic_close'))
        .width($r('app.float.icon_size_small'))
        .height($r('app.float.icon_size_small'))
        .fillColor(this.item.status === ToolCallStatus.CANCELLED ? $r('app.color.icon_muted') : $r('app.color.danger'))
    }
  }

  @Builder
  header() {
    Row({ space: $r('app.float.space_s') }) {
      this.statusIcon()
      Text(this.verb())
        .fontSize($r('app.float.font_s'))
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
      Text(this.item.target)
        .fontFamily(MONO_FONT)
        .fontSize($r('app.float.font_xs'))
        .fontColor(this.isFileTool() ? $r('app.color.text_link') : $r('app.color.text_secondary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(UiConst.LAYOUT_WEIGHT_FILL)
        .onClick(() => {
          if (this.isFileTool()) {
            this.onOpenFile(this.item.target);
          }
        })
      if (this.item.status === ToolCallStatus.DENIED) {
        Text($r('app.string.agent_status_denied'))
          .fontSize($r('app.float.font_xxs'))
          .fontColor($r('app.color.danger'))
      }
      if (this.detail().length > 0 && !this.item.awaitingApproval) {
        Image(this.item.expanded ? $r('app.media.ic_chevron_down') : $r('app.media.ic_chevron_right'))
          .width($r('app.float.icon_size_small'))
          .height($r('app.float.icon_size_small'))
          .fillColor($r('app.color.icon'))
      }
    }
    .width(UiConst.FULL)
    .height(this.touch ? $r('app.float.list_row_compact_touch') : $r('app.float.agent_tool_row_height'))
    .padding({ left: $r('app.float.space_s'), right: $r('app.float.space_s') })
    .onClick(() => {
      this.item.expanded = !this.item.expanded;
    })
  }

  @Builder
  outputBlock(text: string) {
    if (this.isDiff(text)) {
      DiffView({ diff: text })
    } else {
      Scroll() {
        Text(text)
          .fontFamily(MONO_FONT)
          .fontSize($r('app.float.font_xs'))
          .fontColor(this.item.isError ? $r('app.color.danger') : $r('app.color.code_text'))
          .copyOption(CopyOptions.LocalDevice)
          .padding($r('app.float.space_s'))
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width(UiConst.FULL)
      .align(Alignment.Start)
      .backgroundColor($r('app.color.code_bg'))
      .borderRadius($r('app.float.radius_s'))
      .constraintSize({ maxHeight: $r('app.float.agent_output_max_height') })
    }
  }

  @Builder
  approval() {
    Column({ space: $r('app.float.space_s') }) {
      Text(this.approvalTitle())
        .fontSize($r('app.float.font_s'))
        .fontColor($r('app.color.text_primary'))
        .width(UiConst.FULL)
      if (this.item.preview.length > 0) {
        this.outputBlock(this.item.preview)
      }
      Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.resource($r('app.float.space_s')),
        cross: LengthMetrics.resource($r('app.float.space_s')) } }) {
        Button($r('app.string.agent_approve'))
          .fontSize($r('app.float.font_s'))
          .height($r('app.float.button_height'))
          .backgroundColor($r('app.color.button_primary_bg'))
          .fontColor($r('app.color.text_on_accent'))
          .borderRadius($r('app.float.radius_s'))
          .onClick(() => this.onAnswer(ApprovalDecision.APPROVE, ''))
        Button(this.alwaysLabel())
          .fontSize($r('app.float.font_s'))
          .height($r('app.float.button_height'))
          .backgroundColor($r('app.color.button_secondary_bg'))
          .fontColor($r('app.color.button_secondary_text'))
          .borderRadius($r('app.float.radius_s'))
          .onClick(() => this.onAnswer(ApprovalDecision.APPROVE_ALWAYS, ''))
        Button($r('app.string.agent_deny'))
          .fontSize($r('app.float.font_s'))
          .height($r('app.float.button_height'))
          .backgroundColor($r('app.color.button_secondary_bg'))
          .fontColor($r('app.color.danger'))
          .borderRadius($r('app.float.radius_s'))
          .onClick(() => this.onAnswer(ApprovalDecision.DENY, this.feedback))
      }
      TextInput({ text: this.feedback, placeholder: $r('app.string.agent_deny_feedback_placeholder') })
        .attributeModifier(this.inputStyle)
        .width(UiConst.FULL)
        .onChange((v: string) => {
          this.feedback = v;
        })
        .onSubmit(() => {
          if (this.feedback.trim().length > 0) {
            this.onAnswer(ApprovalDecision.DENY, this.feedback);
          }
        })
    }
    .width(UiConst.FULL)
    .padding({ left: $r('app.float.space_s'), right: $r('app.float.space_s'), bottom: $r('app.float.space_s') })
  }

  @Builder
  questionBlock() {
    Column({ space: $r('app.float.space_s') }) {
      Text(this.item.question)
        .fontSize($r('app.float.font_m'))
        .fontColor($r('app.color.text_primary'))
        .fontWeight(FontWeight.Medium)
        .width(UiConst.FULL)
      ForEach(this.item.options, (o: QuestionOption) => {
        Row({ space: $r('app.float.space_s') }) {
          if (this.item.multiSelect) {
            Checkbox()
              .select(this.picked.indexOf(o.label) >= 0)
              .selectedColor($r('app.color.accent'))
              .hitTestBehavior(HitTestMode.None)
          }
          Column({ space: $r('app.float.space_xxs') }) {
            Text(o.label)
              .fontSize($r('app.float.font_s'))
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
            if (o.description.length > 0) {
              Text(o.description)
                .fontSize($r('app.float.font_xs'))
                .fontColor($r('app.color.text_secondary'))
            }
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(UiConst.LAYOUT_WEIGHT_FILL)
        }
        .width(UiConst.FULL)
        .padding($r('app.float.space_s'))
        .backgroundColor(this.picked.indexOf(o.label) >= 0 ? $r('app.color.selected_bg') : $r('app.color.choice_bg'))
        .borderRadius($r('app.float.radius_m'))
        .clickEffect({ level: ClickEffectLevel.LIGHT })
        .onClick(() => this.togglePick(o.label))
      }, (o: QuestionOption) => o.label)
      Row({ space: $r('app.float.space_s') }) {
        TextInput({ text: this.freeText, placeholder: $r('app.string.agent_question_other') })
          .attributeModifier(this.inputStyle)
          .layoutWeight(UiConst.LAYOUT_WEIGHT_FILL)
          .onChange((v: string) => {
            this.freeText = v;
          })
          .onSubmit(() => this.submitAnswer())
        Button($r('app.string.agent_question_send'))
          .fontSize($r('app.float.font_s'))
          .height($r('app.float.button_height'))
          .backgroundColor($r('app.color.button_primary_bg'))
          .fontColor($r('app.color.text_on_accent'))
          .borderRadius($r('app.float.radius_s'))
          .enabled(this.freeText.trim().length > 0 || this.picked.length > 0)
          .onClick(() => this.submitAnswer())
      }
      .width(UiConst.FULL)
      Text($r('app.string.agent_question_skip'))
        .fontSize($r('app.float.font_xs'))
        .fontColor($r('app.color.text_link'))
        .onClick(() => this.onReply(''))
    }
    .width(UiConst.FULL)
    .alignItems(HorizontalAlign.Start)
    .padding({ left: $r('app.float.space_s'), right: $r('app.float.space_s'), bottom: $r('app.float.space_s') })
  }

  build() {
    Column() {
      this.header()
      if (this.item.awaitingAnswer) {
        this.questionBlock()
      } else if (this.item.awaitingApproval) {
        this.approval()
      } else if (this.item.expanded && this.detail().length > 0) {
        Column() {
          this.outputBlock(this.detail())
        }
        .width(UiConst.FULL)
        .padding({ left: $r('app.float.space_s'), right: $r('app.float.space_s'), bottom: $r('app.float.space_s') })
      }
    }
    .width(UiConst.FULL)
    .backgroundColor($r('app.color.card_bg'))
    .borderRadius($r('app.float.radius_m'))
    .border({
      width: $r('app.float.border_width'),
      color: this.item.awaitingApproval ? $r('app.color.warning') :
        (this.item.awaitingAnswer ? $r('app.color.accent') : $r('app.color.border'))
    })
    .shadow(this.item.awaitingApproval || this.item.awaitingAnswer ? ShadowStyle.OUTER_DEFAULT_MD :
      ShadowStyle.OUTER_DEFAULT_XS)
  }
}
