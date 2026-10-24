import { Strings } from '../../core/common/Strings';
import { TimeFormat } from '../../core/common/TimeFormat';
import { GitChange, GitCommit } from '../../core/git/GitTypes';
import { ActionButton, ActionStyle } from '../../components/ActionButton';
import { EmptyState } from '../../components/EmptyState';
import { IconButton } from '../../components/IconButton';
import { TextAreaModifier } from '../../components/Modifiers';
import { SectionHeader } from '../../components/SectionHeader';
import { UiConst } from '../../components/UiConst';
import { MONO_FONT } from '../../components/Fonts';
import { ChangeRow } from './ChangeRow';
import { ScmModel, ScmOp } from './ScmModel';

const SHORT_OID: number = 7;
const MS_PER_SECOND: number = 1000;

/** Source Control: branch, commit box, staged / unstaged changes, recent commits. */
@ComponentV2
export struct ScmView {
  @Param @Require model: ScmModel;
  @Event onPickBranch: () => void = () => {
  };
  private areaStyle: TextAreaModifier = new TextAreaModifier();

  @Builder
  moreMenu() {
    Menu() {
      MenuItem({ content: $r('app.string.scm_fetch') }).onClick(() => this.model.fetch())
      MenuItem({ content: $r('app.string.scm_new_branch') }).onClick(() => this.model.createBranch())
      MenuItem({ content: $r('app.string.scm_set_remote') }).onClick(() => this.model.setRemote())
      MenuItem({ content: $r('app.string.scm_stage_all') }).onClick(() => this.model.stageAll())
      MenuItem({ content: $r('app.string.scm_unstage_all') }).onClick(() => this.model.unstageAll())
    }
  }

  @Builder
  headerActions() {
    IconButton({ icon: $r('app.media.ic_refresh'), label: $r('app.string.action_refresh'),
      onTap: () => this.model.refresh() })
    IconButton({ icon: $r('app.media.ic_download'), label: $r('app.string.scm_pull'),
      isEnabled: this.model.busy === ScmOp.NONE, onTap: () => this.model.pull() })
    IconButton({ icon: $r('app.media.ic_upload'), label: $r('app.string.scm_push'),
      isEnabled: this.model.busy === ScmOp.NONE, onTap: () => this.model.push() })
    Button({ type: ButtonType.Normal }) {
      Image($r('app.media.ic_more'))
        .width($r('app.float.icon_size'))
        .height($r('app.float.icon_size'))
        .fillColor($r('app.color.icon'))
    }
    .width($r('app.float.icon_button_size'))
    .height($r('app.float.icon_button_size'))
    .backgroundColor(Color.Transparent)
    .accessibilityText($r('app.string.action_more'))
    .bindMenu(this.moreMenu())
  }

  @Builder
  sectionHeader(title: string, count: number, actionIcon: Resource, actionLabel: Resource, onAction: () => void) {
    Row() {
      Text(Strings.get('scm_section_count', title, count))
        .fontSize($r('app.float.font_xs'))
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_secondary'))
        .layoutWeight(UiConst.LAYOUT_WEIGHT_FILL)
      IconButton({ icon: actionIcon, label: actionLabel, onTap: onAction })
    }
    .width(UiConst.FULL)
    .height($r('app.float.section_header_height'))
    .padding({ left: $r('app.float.space_m'), right: $r('app.float.space_xs') })
    .backgroundColor($r('app.color.sidebar_bg'))
  }

  @Builder
  commitBox() {
    Column({ space: $r('app.float.space_s') }) {
      Row({ space: $r('app.float.space_xs') }) {
        Image($r('app.media.ic_git_branch'))
          .width($r('app.float.icon_size_small'))
          .height($r('app.float.icon_size_small'))
          .fillColor($r('app.color.icon'))
        Text(this.model.branch.length > 0 ? this.model.branch : Strings.get('scm_no_branch'))
          .fontSize($r('app.float.font_s'))
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(UiConst.LAYOUT_WEIGHT_FILL)
        Image($r('app.media.ic_chevron_down'))
          .width($r('app.float.icon_size_small'))
          .height($r('app.float.icon_size_small'))
          .fillColor($r('app.color.icon'))
      }
      .width(UiConst.FULL)
      .onClick(() => this.onPickBranch())
      TextArea({ text: this.model.message, placeholder: $r('app.string.scm_message_placeholder') })
        .attributeModifier(this.areaStyle)
        .width(UiConst.FULL)
        .constraintSize({ minHeight: $r('app.float.commit_box_min_height') })
        .onChange((v: string) => {
          this.model.message = v;
        })
      ActionButton({
        text: this.model.busy === ScmOp.COMMIT ? $r('app.string.scm_committing') : $r('app.string.scm_commit'),
        icon: $r('app.media.ic_check'),
        kind: ActionStyle.PRIMARY,
        stretch: true,
        isEnabled: this.model.busy === ScmOp.NONE && this.model.message.trim().length > 0,
        onTap: () => this.model.commit()
      })
      if (this.model.progress.length > 0) {
        Text(this.model.progress)
          .fontSize($r('app.float.font_xs'))
          .fontColor($r('app.color.text_secondary'))
          .width(UiConst.FULL)
      }
    }
    .padding({ left: $r('app.float.space_m'), right: $r('app.float.space_m'), bottom: $r('app.float.space_s') })
  }

  @Builder
  commitRow(c: GitCommit) {
    Column({ space: $r('app.float.space_xxs') }) {
      Text(c.message.split('\n')[0])
        .fontSize($r('app.float.font_s'))
        .fontColor($r('app.color.text_primary'))
        .maxLines(UiConst.MAX_LINES_TITLE)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width(UiConst.FULL)
      Text(Strings.get('scm_commit_meta', c.oid.substring(0, SHORT_OID), c.authorName,
        TimeFormat.relative(c.timestamp * MS_PER_SECOND)))
        .fontSize($r('app.float.font_xs'))
        .fontFamily(MONO_FONT)
        .fontColor($r('app.color.text_muted'))
        .maxLines(UiConst.MAX_LINES_TITLE)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width(UiConst.FULL)
    }
    .padding({
      left: $r('app.float.space_l'), right: $r('app.float.space_m'),
      top: $r('app.float.space_xs'), bottom: $r('app.float.space_xs')
    })
  }

  @Builder
  notRepo() {
    EmptyState({
      icon: $r('app.media.ic_git_branch'),
      title: $r('app.string.scm_not_repo_title'),
      message: $r('app.string.scm_not_repo_message')
    }) {
      ActionButton({ text: $r('app.string.scm_init'), kind: ActionStyle.PRIMARY, onTap: () => this.model.init() })
    }
  }

  build() {
    Column() {
      SectionHeader({ title: $r('app.string.scm_title') }) {
        if (this.model.isRepo) {
          this.headerActions()
        }
      }
      if (!this.model.loaded) {
        Text($r('app.string.scm_loading'))
          .fontSize($r('app.float.font_s'))
          .fontColor($r('app.color.text_secondary'))
          .padding($r('app.float.space_l'))
      } else if (!this.model.isRepo) {
        this.notRepo()
      } else {
        this.commitBox()
        List() {
          if (this.model.staged.length > 0) {
            ListItemGroup({
              header: this.sectionHeader(Strings.get('scm_staged'), this.model.staged.length, $r('app.media.ic_remove'),
                $r('app.string.scm_unstage_all'), () => this.model.unstageAll())
            }) {
              ForEach(this.model.staged, (c: GitChange) => {
                ListItem() {
                  ChangeRow({
                    change: c,
                    onOpen: () => this.model.openChange(c),
                    onUnstage: () => this.model.unstage(c)
                  })
                }
              }, (c: GitChange) => 'S' + c.code + c.path)
            }
          }
          ListItemGroup({
            header: this.sectionHeader(Strings.get('scm_changes'), this.model.unstaged.length, $r('app.media.ic_add'),
              $r('app.string.scm_stage_all'), () => this.model.stageAll())
          }) {
            ForEach(this.model.unstaged, (c: GitChange) => {
              ListItem() {
                ChangeRow({
                  change: c,
                  onOpen: () => this.model.openChange(c),
                  onStage: () => this.model.stage(c),
                  onDiscard: () => this.model.discard(c)
                })
              }
            }, (c: GitChange) => 'U' + c.code + c.path)
          }
          if (this.model.commits.length > 0) {
            ListItemGroup({
              header: this.sectionHeader(Strings.get('scm_commits'), this.model.commits.length,
                $r('app.media.ic_refresh'), $r('app.string.action_refresh'), () => this.model.refresh())
            }) {
              ForEach(this.model.commits, (c: GitCommit) => {
                ListItem() {
                  this.commitRow(c)
                }
              }, (c: GitCommit) => c.oid)
            }
          }
        }
        .sticky(StickyStyle.Header)
        .layoutWeight(UiConst.LAYOUT_WEIGHT_FILL)
        .scrollBar(BarState.Auto)
      }
    }
    .width(UiConst.FULL)
    .height(UiConst.FULL)
    .backgroundColor($r('app.color.sidebar_bg'))
  }
}
