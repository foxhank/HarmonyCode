import { curves } from '@kit.ArkUI';
import { Strings } from '../../core/common/Strings';
import { ConnState } from '../../core/remote/RemoteConnection';
import { hostAddress } from '../../core/remote/RemoteHost';
import { agentSettings } from '../../core/settings/AgentSettingsStore';
import { settingsStore } from '../../core/settings/SettingsStore';
import { ActionButton, ActionStyle } from '../../components/ActionButton';
import { IconButton } from '../../components/IconButton';
import { GlassBarModifier, StatusDot } from '../../components/Surface';
import { UiConst } from '../../components/UiConst';
import { AgentPanel } from '../agent/views/AgentPanel';
import { appNav, Routes } from '../app/AppNavigation';
import { layoutState } from '../app/LayoutState';
import { dialogs } from '../dialogs/DialogModel';
import { toasts } from '../dialogs/ToastModel';
import { ExtraKeys } from '../terminal/ExtraKeys';
import { TerminalWebView } from '../terminal/TerminalWebView';
import { RemoteFilesView } from './RemoteFilesView';
import { remoteHosts } from './RemoteHostsStore';
import { RemoteTab, RemoteWorkspace } from './RemoteWorkspace';

interface TabItem {
  id: string;
  icon: Resource;
  label: Resource;
}

/**
 * Working on one of the user's computers: the agent with full access, a terminal and a file
 * browser, all over one SSH connection. Phones switch between them with a bottom bar; wider
 * screens show the agent next to the terminal or files.
 */
@ComponentV2
export struct RemotePage {
  @Local ws: RemoteWorkspace | undefined = undefined;
  /** Wide layout: what the right pane shows. */
  @Local side: string = RemoteTab.TERMINAL;
  private glass: GlassBarModifier = new GlassBarModifier();

  private open(hostId: string): void {
    const host = remoteHosts.get(hostId);
    if (host === undefined) {
      toasts.error(Strings.get('remote_missing'));
      appNav.pop();
      return;
    }
    agentSettings.ensureLoaded(getContext(this));
    const ws = new RemoteWorkspace(host, settingsStore, dialogs, toasts);
    this.ws = ws;
    ws.connect();
  }

  aboutToDisappear(): void {
    if (this.ws !== undefined) {
      this.ws.dispose();
      this.ws = undefined;
    }
  }

  private tabs(): TabItem[] {
    return [
      { id: RemoteTab.AGENT, icon: $r('app.media.ic_agent'), label: $r('app.string.nav_agent') },
      { id: RemoteTab.TERMINAL, icon: $r('app.media.ic_terminal'), label: $r('app.string.nav_terminal') },
      { id: RemoteTab.FILES, icon: $r('app.media.ic_files'), label: $r('app.string.nav_files') },
    ];
  }

  private stateColor(ws: RemoteWorkspace): ResourceColor {
    if (ws.state === ConnState.CONNECTED) {
      return $r('app.color.status_online');
    }
    if (ws.state === ConnState.CONNECTING) {
      return $r('app.color.warning');
    }
    return ws.state === ConnState.FAILED ? $r('app.color.danger') : $r('app.color.icon_muted');
  }

  private stateText(ws: RemoteWorkspace): string {
    if (ws.state === ConnState.CONNECTED) {
      return ws.platform.length > 0 ? ws.platform : Strings.get('remote_state_connected');
    }
    if (ws.state === ConnState.CONNECTING) {
      return Strings.get('remote_state_connecting');
    }
    if (ws.state === ConnState.FAILED) {
      return Strings.get('remote_state_disconnected');
    }
    return hostAddress(ws.host);
  }

  @Builder
  header(ws: RemoteWorkspace) {
    Row({ space: $r('app.float.space_s') }) {
      IconButton({
        icon: $r('app.media.ic_arrow_back'), label: $r('app.string.action_back'),
        buttonSize: $r('app.float.icon_button_size_touch'), onTap: () => appNav.pop()
      })
      Column({ space: $r('app.float.space_xxs') }) {
        Text(ws.host.name)
          .fontSize($r('app.float.font_l'))
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(UiConst.MAX_LINES_TITLE)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Row({ space: $r('app.float.space_xs') }) {
          StatusDot({ color: this.stateColor(ws), glow: ws.state === ConnState.CONNECTED })
          Text(this.stateText(ws))
            .fontSize($r('app.float.font_xs'))
            .fontColor($r('app.color.text_secondary'))
            .maxLines(UiConst.MAX_LINES_TITLE)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(UiConst.LAYOUT_WEIGHT_FILL)
      if (ws.state === ConnState.FAILED || ws.state === ConnState.IDLE) {
        IconButton({
          icon: $r('app.media.ic_refresh'), label: $r('app.string.remote_reconnect'),
          buttonSize: $r('app.float.icon_button_size_touch'), onTap: () => ws.connect()
        })
      }
      IconButton({
        icon: $r('app.media.ic_settings'), label: $r('app.string.remote_edit'),
        buttonSize: $r('app.float.icon_button_size_touch'),
        onTap: () => appNav.pushPathByName(Routes.HOST_EDITOR, ws.host.id)
      })
    }
    .width(UiConst.FULL)
    .height($r('app.float.page_header_height'))
    .padding({ left: $r('app.float.space_s'), right: $r('app.float.space_s') })
  }

  /** Before the first connection: progress, or what went wrong with a way forward. */
  @Builder
  connecting(ws: RemoteWorkspace) {
    Column({ space: $r('app.float.space_l') }) {
      if (ws.state === ConnState.FAILED) {
        Image($r('app.media.ic_computer'))
          .width($r('app.float.empty_icon_size'))
          .height($r('app.float.empty_icon_size'))
          .fillColor($r('app.color.danger'))
        Text($r('app.string.remote_connect_failed'))
          .fontSize($r('app.float.font_l'))
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        Text(ws.error)
          .fontSize($r('app.float.font_s'))
          .fontColor($r('app.color.text_secondary'))
          .textAlign(TextAlign.Center)
          .copyOption(CopyOptions.LocalDevice)
        Row({ space: $r('app.float.space_s') }) {
          ActionButton({ text: $r('app.string.remote_retry'), kind: ActionStyle.PRIMARY, onTap: () => ws.connect() })
          ActionButton({
            text: $r('app.string.remote_edit'), kind: ActionStyle.SECONDARY,
            onTap: () => appNav.pushPathByName(Routes.HOST_EDITOR, ws.host.id)
          })
        }
        Text($r('app.string.remote_connect_tips'))
          .fontSize($r('app.float.font_xs'))
          .fontColor($r('app.color.text_muted'))
          .textAlign(TextAlign.Center)
      } else {
        LoadingProgress()
          .width($r('app.float.empty_icon_size'))
          .height($r('app.float.empty_icon_size'))
          .color($r('app.color.accent'))
        Text(Strings.get('remote_connecting_to', hostAddress(ws.host)))
          .fontSize($r('app.float.font_m'))
          .fontColor($r('app.color.text_secondary'))
      }
    }
    .width(UiConst.FULL)
    .layoutWeight(UiConst.LAYOUT_WEIGHT_FILL)
    .padding($r('app.float.space_xl'))
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  terminal(ws: RemoteWorkspace) {
    Column() {
      TerminalWebView({ model: ws.terminal })
        .layoutWeight(UiConst.LAYOUT_WEIGHT_FILL)
      if (!layoutState.isDesktop) {
        ExtraKeys({ model: ws.terminal })
      }
    }
    .width(UiConst.FULL)
    .height(UiConst.FULL)
    .backgroundColor($r('app.color.terminal_bg'))
  }

  @Builder
  phoneBody(ws: RemoteWorkspace) {
    // All three stay mounted so the terminal and agent keep their state when switching tabs.
    Stack() {
      Column() {
        AgentPanel({ model: ws.agent, touch: true })
      }
      .visibility(ws.tab === RemoteTab.AGENT ? Visibility.Visible : Visibility.Hidden)
      Column() {
        this.terminal(ws)
      }
      .visibility(ws.tab === RemoteTab.TERMINAL ? Visibility.Visible : Visibility.Hidden)
      Column() {
        RemoteFilesView({ model: ws.files, touch: true })
      }
      .visibility(ws.tab === RemoteTab.FILES ? Visibility.Visible : Visibility.Hidden)
    }
    .width(UiConst.FULL)
    .layoutWeight(UiConst.LAYOUT_WEIGHT_FILL)
    Row() {
      ForEach(this.tabs(), (t: TabItem) => {
        Column({ space: $r('app.float.space_xxs') }) {
          Image(t.icon)
            .width($r('app.float.icon_size'))
            .height($r('app.float.icon_size'))
            .fillColor(ws.tab === t.id ? $r('app.color.accent') : $r('app.color.icon'))
          Text(t.label)
            .fontSize($r('app.float.font_xxs'))
            .fontColor(ws.tab === t.id ? $r('app.color.accent') : $r('app.color.text_secondary'))
        }
        .layoutWeight(UiConst.LAYOUT_WEIGHT_FILL)
        .height(UiConst.FULL)
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          this.getUIContext().animateTo({ curve: curves.springMotion(UiConst.SPRING_RESPONSE, UiConst.SPRING_DAMPING) }, () => {
            ws.tab = t.id;
          });
        })
        .accessibilityText(t.label)
      }, (t: TabItem) => t.id)
    }
    .attributeModifier(this.glass)
    .width(UiConst.FULL)
    .height($r('app.float.bottomnav_height'))
  }

  @Builder
  wideBody(ws: RemoteWorkspace) {
    Row() {
      Column() {
        AgentPanel({ model: ws.agent, touch: !layoutState.isDesktop })
      }
      .layoutWeight(UiConst.REMOTE_AGENT_WEIGHT)
      .height(UiConst.FULL)
      Divider().vertical(true).color($r('app.color.border'))
      Column() {
        Row({ space: $r('app.float.space_xs') }) {
          ForEach([this.tabs()[1], this.tabs()[2]], (t: TabItem) => {
            Row({ space: $r('app.float.space_xs') }) {
              Image(t.icon)
                .width($r('app.float.icon_size_small'))
                .height($r('app.float.icon_size_small'))
                .fillColor(this.side === t.id ? $r('app.color.accent') : $r('app.color.icon'))
              Text(t.label)
                .fontSize($r('app.float.font_s'))
                .fontColor(this.side === t.id ? $r('app.color.text_primary') : $r('app.color.text_secondary'))
            }
            .padding({ left: $r('app.float.space_m'), right: $r('app.float.space_m') })
            .height($r('app.float.button_height'))
            .borderRadius($r('app.float.radius_m'))
            .backgroundColor(this.side === t.id ? $r('app.color.selected_bg') : Color.Transparent)
            .onClick(() => {
              this.side = t.id;
            })
          }, (t: TabItem) => t.id)
        }
        .width(UiConst.FULL)
        .padding($r('app.float.space_xs'))
        Stack() {
          Column() {
            this.terminal(ws)
          }
          .visibility(this.side === RemoteTab.TERMINAL ? Visibility.Visible : Visibility.Hidden)
          Column() {
            RemoteFilesView({ model: ws.files, touch: !layoutState.isDesktop })
          }
          .visibility(this.side === RemoteTab.FILES ? Visibility.Visible : Visibility.Hidden)
        }
        .layoutWeight(UiConst.LAYOUT_WEIGHT_FILL)
      }
      .layoutWeight(UiConst.REMOTE_TOOLS_WEIGHT)
      .height(UiConst.FULL)
    }
    .width(UiConst.FULL)
    .layoutWeight(UiConst.LAYOUT_WEIGHT_FILL)
  }

  @Builder
  body(ws: RemoteWorkspace) {
    Column() {
      this.header(ws)
      if (!ws.ready) {
        this.connecting(ws)
      } else if (layoutState.isPhone) {
        this.phoneBody(ws)
      } else {
        this.wideBody(ws)
      }
    }
    .width(UiConst.FULL)
    .height(UiConst.FULL)
  }

  build() {
    NavDestination() {
      if (this.ws !== undefined) {
        this.body(this.ws)
      }
    }
    .hideTitleBar(true)
    .backgroundColor($r('app.color.app_bg'))
    .onReady((ctx: NavDestinationContext) => {
      this.open(ctx.pathInfo.param as string);
    })
  }
}
