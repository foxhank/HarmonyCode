import { Strings } from '../../core/common/Strings';
import { TimeFormat } from '../../core/common/TimeFormat';
import { copyProject, runsOnDesktop, runsRemotely } from '../../core/project/ProjectInfo';
import { projectRepository } from '../../core/project/ProjectRepository';
import { hostAddress, RemoteHost } from '../../core/remote/RemoteHost';
import { ActionButton, ActionStyle } from '../../components/ActionButton';
import { MONO_FONT } from '../../components/Fonts';
import { IconButton } from '../../components/IconButton';
import { InputModifier } from '../../components/Modifiers';
import { ElevatedCardModifier, IconTile, StatusDot } from '../../components/Surface';
import { UiConst } from '../../components/UiConst';
import { openWorkbench } from '../app/AppNavigation';
import { CatalogText } from '../app/CatalogText';
import { RemoteHostsStore, remoteHosts } from '../remote/RemoteHostsStore';
import { RunTarget, TargetState } from '../remote/RunTarget';
import { DesktopsStore, desktops, PairedDesktop } from '../link/DesktopsStore';
import { DesktopTarget } from '../link/DesktopTarget';
import { Workspace } from '../workbench/Workspace';
import { ToolsModel, ToolState } from './ToolsModel';

/** Value of the "run on" choice meaning this device. */
const ON_DEVICE: string = '';
/** Prefix of "run on" values for paired desktops (computers use their host id). */
const DESKTOP: string = 'desktop:';

/**
 * Where a project runs and what it has: this device's Linux VM with one-tap languages and tools,
 * or one of the user's computers, with the project mirrored there and synced both ways.
 */
@ComponentV2
export struct EnvironmentPanel {
  @Param @Require ws: Workspace;
  @Param touch: boolean = true;
  @Event onClose: () => void = () => {
  };
  @Local choice: string = ON_DEVICE;
  @Local folder: string = '';
  @Local hosts: RemoteHostsStore = remoteHosts;
  @Local desks: DesktopsStore = desktops;
  private card: ElevatedCardModifier = new ElevatedCardModifier();
  private inputStyle: InputModifier = new InputModifier();

  aboutToAppear(): void {
    this.choice = this.currentChoice();
    this.folder = this.ws.project.remoteDir ?? '';
  }

  private currentChoice(): string {
    const p = this.ws.project;
    if (runsOnDesktop(p)) {
      return DESKTOP + (p.desktopId as string);
    }
    return runsRemotely(p) ? p.remoteHostId as string : ON_DEVICE;
  }

  private changed(): boolean {
    return this.choice !== this.currentChoice() ||
      (this.choice !== ON_DEVICE && this.folder.trim() !== (this.ws.project.remoteDir ?? ''));
  }

  private onDesktop(): boolean {
    return this.choice.startsWith(DESKTOP);
  }

  /** Saves the choice and reopens the project so the terminal, Run and the agent use it. */
  private async apply(): Promise<void> {
    if (!await this.ws.editor.closeAll()) {
      return;
    }
    const p = copyProject(this.ws.project);
    p.desktopId = this.onDesktop() ? this.choice.substring(DESKTOP.length) : '';
    p.remoteHostId = this.onDesktop() ? '' : this.choice;
    p.remoteDir = this.choice === ON_DEVICE ? '' : this.folder.trim();
    projectRepository.update(p);
    openWorkbench(p.id);
  }

  @Builder
  sectionTitle(title: ResourceStr) {
    Text(title)
      .fontSize($r('app.float.font_xs'))
      .fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.text_muted'))
      .textCase(TextCase.UpperCase)
      .width(UiConst.FULL)
  }

  @Builder
  choiceRow(id: string, icon: Resource, title: string, subtitle: string) {
    Row({ space: $r('app.float.space_m') }) {
      IconTile({ icon: icon })
      Column({ space: $r('app.float.space_xxs') }) {
        Text(title)
          .fontSize($r('app.float.font_m'))
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(UiConst.MAX_LINES_TITLE)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(subtitle)
          .fontSize($r('app.float.font_xs'))
          .fontColor($r('app.color.text_secondary'))
          .maxLines(UiConst.MAX_LINES_TITLE)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(UiConst.LAYOUT_WEIGHT_FILL)
      Radio({ value: id, group: 'runOn' })
        .checked(this.choice === id)
        .hitTestBehavior(HitTestMode.None)
    }
    .width(UiConst.FULL)
    .padding($r('app.float.space_s'))
    .borderRadius($r('app.float.radius_m'))
    .backgroundColor(this.choice === id ? $r('app.color.accent_soft') : Color.Transparent)
    .clickEffect({ level: ClickEffectLevel.LIGHT })
    .onClick(() => {
      this.choice = id;
    })
  }

  @Builder
  runOnSection() {
    Column({ space: $r('app.float.space_s') }) {
      this.sectionTitle($r('app.string.env_run_on'))
      this.choiceRow(ON_DEVICE, $r('app.media.ic_terminal'), Strings.get('env_this_device'),
        CatalogText.envName(this.ws.project.envId))
      ForEach(this.desks.desktops, (d: PairedDesktop) => {
        this.choiceRow(DESKTOP + d.id, $r('app.media.ic_link'), d.name, Strings.get('env_desktop_subtitle', d.os))
      }, (d: PairedDesktop) => d.id)
      ForEach(this.hosts.sorted(), (h: RemoteHost) => {
        this.choiceRow(h.id, $r('app.media.ic_computer'), h.name, hostAddress(h))
      }, (h: RemoteHost) => h.id)
      if (this.hosts.hosts.length === 0 && this.desks.desktops.length === 0) {
        Text($r('app.string.env_no_computers'))
          .fontSize($r('app.float.font_xs'))
          .fontColor($r('app.color.text_muted'))
          .width(UiConst.FULL)
      }
      if (this.choice !== ON_DEVICE) {
        Column({ space: $r('app.float.space_xs') }) {
          Text(this.onDesktop() ? $r('app.string.env_desktop_folder') : $r('app.string.env_remote_folder'))
            .fontSize($r('app.float.font_s'))
            .fontColor($r('app.color.text_secondary'))
            .width(UiConst.FULL)
          TextInput({
            text: this.folder,
            placeholder: this.onDesktop() ? DesktopTarget.folderFor(this.ws.project) :
              Strings.get('env_remote_folder_default', this.ws.project.name)
          })
            .attributeModifier(this.inputStyle)
            .width(UiConst.FULL)
            .onChange((v: string) => {
              this.folder = v;
            })
          Text(this.onDesktop() ? $r('app.string.env_desktop_hint') : $r('app.string.env_remote_hint'))
            .fontSize($r('app.float.font_xs'))
            .fontColor($r('app.color.text_muted'))
            .width(UiConst.FULL)
        }
        .width(UiConst.FULL)
      }
      if (this.changed()) {
        ActionButton({ text: $r('app.string.env_apply'), kind: ActionStyle.PRIMARY, onTap: () => this.apply() })
      }
    }
    .attributeModifier(this.card)
    .width(UiConst.FULL)
    .padding($r('app.float.space_l'))
  }

  @Builder
  syncSection(r: RunTarget) {
    Column({ space: $r('app.float.space_s') }) {
      this.sectionTitle($r('app.string.env_sync'))
      Row({ space: $r('app.float.space_s') }) {
        StatusDot({
          color: r.state === TargetState.CONNECTED ? $r('app.color.status_online') :
            (r.state === TargetState.FAILED ? $r('app.color.danger') : $r('app.color.warning')),
          glow: r.state === TargetState.CONNECTED
        })
        Text(r.label())
          .fontSize($r('app.float.font_s'))
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(UiConst.LAYOUT_WEIGHT_FILL)
          .maxLines(UiConst.MAX_LINES_TITLE)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (r.syncing) {
          LoadingProgress()
            .width($r('app.float.icon_size'))
            .height($r('app.float.icon_size'))
            .color($r('app.color.accent'))
        }
      }
      .width(UiConst.FULL)
      if (r.remoteDir.length > 0) {
        Text(r.remoteDir)
          .fontFamily(MONO_FONT)
          .fontSize($r('app.float.font_xs'))
          .fontColor($r('app.color.code_text'))
          .width(UiConst.FULL)
          .copyOption(CopyOptions.LocalDevice)
      }
      Text(r.lastSync > 0 ? Strings.get('env_last_sync', TimeFormat.relative(r.lastSync), r.lastSummary) :
        Strings.get('env_never_synced'))
        .fontSize($r('app.float.font_xs'))
        .fontColor($r('app.color.text_secondary'))
        .width(UiConst.FULL)
      if (r.conflicts.length > 0) {
        Text(Strings.get('env_conflicts', r.conflicts.join(', ')))
          .fontSize($r('app.float.font_xs'))
          .fontColor($r('app.color.warning'))
          .width(UiConst.FULL)
      }
      if (r.error.length > 0) {
        Text(r.error)
          .fontSize($r('app.float.font_xs'))
          .fontColor($r('app.color.danger'))
          .width(UiConst.FULL)
          .copyOption(CopyOptions.LocalDevice)
      }
      ActionButton({
        text: $r('app.string.cmd_sync_remote'), icon: $r('app.media.ic_refresh'), kind: ActionStyle.SECONDARY,
        isEnabled: !r.syncing, onTap: () => {
          this.ws.editor.saveAll();
          r.syncNow();
        }
      })
      Text($r('app.string.env_sync_hint'))
        .fontSize($r('app.float.font_xs'))
        .fontColor($r('app.color.text_muted'))
        .width(UiConst.FULL)
    }
    .attributeModifier(this.card)
    .width(UiConst.FULL)
    .padding($r('app.float.space_l'))
  }

  @Builder
  toolRow(m: ToolsModel, t: ToolState) {
    Row({ space: $r('app.float.space_m') }) {
      Text(t.def.badge)
        .fontSize($r('app.float.font_s'))
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_on_accent'))
        .textAlign(TextAlign.Center)
        .width($r('app.float.icon_tile_size'))
        .height($r('app.float.icon_tile_size'))
        .borderRadius($r('app.float.radius_m'))
        .backgroundColor(t.def.color)
      Column({ space: $r('app.float.space_xxs') }) {
        Text(t.name)
          .fontSize($r('app.float.font_m'))
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        Text(t.installed ? t.version : (t.known ? Strings.get('tools_not_installed') : Strings.get('tool_' + t.def.id + '_detail')))
          .fontSize($r('app.float.font_xs'))
          .fontColor(t.installed ? $r('app.color.status_online') : $r('app.color.text_secondary'))
          .maxLines(UiConst.MAX_LINES_TITLE)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(UiConst.LAYOUT_WEIGHT_FILL)
      if (m.busyId === t.def.id) {
        LoadingProgress()
          .width($r('app.float.icon_size'))
          .height($r('app.float.icon_size'))
          .color($r('app.color.accent'))
      } else if (t.known) {
        ActionButton({
          text: t.installed ? $r('app.string.tools_remove') : $r('app.string.tools_install'),
          kind: t.installed ? ActionStyle.SECONDARY : ActionStyle.PRIMARY, isEnabled: !m.busy,
          buttonHeight: $r('app.float.list_row_compact_touch'),
          onTap: () => {
            if (t.installed) {
              m.remove(t);
            } else {
              m.install(t);
            }
          }
        })
      }
    }
    .width(UiConst.FULL)
    .padding({ top: $r('app.float.space_xs'), bottom: $r('app.float.space_xs') })
  }

  @Builder
  toolsSection(m: ToolsModel) {
    Column({ space: $r('app.float.space_s') }) {
      Row() {
        Column() {
          this.sectionTitle($r('app.string.tools_title'))
        }
        .layoutWeight(UiConst.LAYOUT_WEIGHT_FILL)
        if (m.checking) {
          LoadingProgress()
            .width($r('app.float.icon_size'))
            .height($r('app.float.icon_size'))
            .color($r('app.color.accent'))
        } else {
          IconButton({ icon: $r('app.media.ic_refresh'), label: $r('app.string.action_refresh'),
            isEnabled: !m.busy && this.ws.terminal.usingVm, onTap: () => m.refresh() })
        }
      }
      .width(UiConst.FULL)
      if (!this.ws.terminal.usingVm) {
        Text($r('app.string.tools_need_vm'))
          .fontSize($r('app.float.font_s'))
          .fontColor($r('app.color.text_secondary'))
          .width(UiConst.FULL)
      } else {
        Text($r('app.string.tools_hint'))
          .fontSize($r('app.float.font_xs'))
          .fontColor($r('app.color.text_muted'))
          .width(UiConst.FULL)
        ForEach(m.tools, (t: ToolState) => {
          this.toolRow(m, t)
        }, (t: ToolState) => t.def.id)
        if (m.error.length > 0) {
          Text(m.error)
            .fontSize($r('app.float.font_xs'))
            .fontColor($r('app.color.danger'))
            .width(UiConst.FULL)
            .copyOption(CopyOptions.LocalDevice)
        }
        if (m.log.length > 0) {
          Scroll() {
            Text(m.log)
              .fontFamily(MONO_FONT)
              .fontSize($r('app.float.font_xxs'))
              .fontColor($r('app.color.code_text'))
              .width(UiConst.FULL)
              .padding($r('app.float.space_s'))
          }
          .width(UiConst.FULL)
          .constraintSize({ maxHeight: $r('app.float.agent_output_max_height') })
          .backgroundColor($r('app.color.code_bg'))
          .borderRadius($r('app.float.radius_m'))
          .initialOffset({ yOffset: Number.MAX_SAFE_INTEGER })
          if (m.busyId.length > 0) {
            ActionButton({ text: $r('app.string.agent_stop'), kind: ActionStyle.DANGER, onTap: () => m.stop() })
          }
        }
      }
    }
    .attributeModifier(this.card)
    .width(UiConst.FULL)
    .padding($r('app.float.space_l'))
  }

  build() {
    Column() {
      Row() {
        Text($r('app.string.env_title'))
          .fontSize($r('app.float.font_l'))
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(UiConst.LAYOUT_WEIGHT_FILL)
        IconButton({
          icon: $r('app.media.ic_close'), label: $r('app.string.action_close'),
          buttonSize: this.touch ? $r('app.float.icon_button_size_touch') : $r('app.float.icon_button_size'),
          onTap: () => this.onClose()
        })
      }
      .width(UiConst.FULL)
      .height($r('app.float.page_header_height'))
      .padding({ left: $r('app.float.space_l'), right: $r('app.float.space_s') })
      Scroll() {
        Column({ space: $r('app.float.space_l') }) {
          this.runOnSection()
          if (this.ws.target !== null) {
            this.syncSection(this.ws.target as RunTarget)
          } else if (this.ws.tools !== null) {
            this.toolsSection(this.ws.tools as ToolsModel)
          }
        }
        .width(UiConst.FULL)
        .padding({ left: $r('app.float.space_l'), right: $r('app.float.space_l'), bottom: $r('app.float.space_xl') })
      }
      .layoutWeight(UiConst.LAYOUT_WEIGHT_FILL)
      .align(Alignment.Top)
      .edgeEffect(EdgeEffect.Spring)
    }
    .width(UiConst.FULL)
    .height(UiConst.FULL)
    .backgroundColor($r('app.color.app_bg'))
  }
}
