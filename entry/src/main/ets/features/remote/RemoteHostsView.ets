import { pasteboard } from '@kit.BasicServicesKit';
import { Strings } from '../../core/common/Strings';
import { AuthMethod, hostAddress, RemoteHost } from '../../core/remote/RemoteHost';
import { ActionButton, ActionStyle } from '../../components/ActionButton';
import { EmptyState } from '../../components/EmptyState';
import { MONO_FONT } from '../../components/Fonts';
import { IconButton } from '../../components/IconButton';
import { ElevatedCardModifier, IconTile } from '../../components/Surface';
import { UiConst } from '../../components/UiConst';
import { appNav, Routes } from '../app/AppNavigation';
import { ButtonRole, dialogs } from '../dialogs/DialogModel';
import { toasts } from '../dialogs/ToastModel';
import { RemoteHostsStore, remoteHosts } from './RemoteHostsStore';

/** Copies text to the clipboard and confirms with a toast. */
export function copyText(text: string, confirmation: string): void {
  try {
    const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
    pasteboard.getSystemPasteboard().setDataSync(data);
    toasts.info(confirmation);
  } catch (e) {
    toasts.error((e as Error).message);
  }
}

/**
 * The start screen's "Remote" section: the user's computers as cards, and HarmonyCode's access
 * key (the public half goes into each computer's authorized_keys).
 */
@ComponentV2
export struct RemoteHostsView {
  @Param touch: boolean = false;
  @Local store: RemoteHostsStore = remoteHosts;
  private card: ElevatedCardModifier = new ElevatedCardModifier();

  private open(h: RemoteHost): void {
    remoteHosts.touch(h.id);
    appNav.pushPathByName(Routes.REMOTE, h.id);
  }

  private edit(id: string): void {
    appNav.pushPathByName(Routes.HOST_EDITOR, id);
  }

  private async remove(h: RemoteHost): Promise<void> {
    const choice = await dialogs.confirm(Strings.get('remote_delete_title'), Strings.get('remote_delete_message', h.name), [
      { label: $r('app.string.action_cancel'), role: ButtonRole.NORMAL },
      { label: $r('app.string.action_delete'), role: ButtonRole.DANGER }
    ]);
    if (choice === 1) {
      remoteHosts.remove(h.id);
    }
  }

  private subtitle(h: RemoteHost): string {
    const parts: string[] = [hostAddress(h)];
    if (h.jumpHostId.length > 0) {
      const via = remoteHosts.get(h.jumpHostId);
      if (via !== undefined) {
        parts.push(Strings.get('remote_via', via.name));
      }
    }
    return parts.join(' · ');
  }

  @Builder
  hostMenu(h: RemoteHost) {
    Menu() {
      MenuItem({ content: $r('app.string.remote_edit') }).onClick(() => this.edit(h.id))
      MenuItem({ content: $r('app.string.action_delete') }).onClick(() => this.remove(h))
    }
  }

  @Builder
  hostCard(h: RemoteHost) {
    Column() {
      Row({ space: $r('app.float.space_m') }) {
        IconTile({ icon: $r('app.media.ic_computer') })
        Column({ space: $r('app.float.space_xxs') }) {
          Text(h.name)
            .fontSize($r('app.float.font_m'))
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .maxLines(UiConst.MAX_LINES_TITLE)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.subtitle(h))
            .fontSize($r('app.float.font_xs'))
            .fontColor($r('app.color.text_secondary'))
            .maxLines(UiConst.MAX_LINES_TITLE)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(UiConst.LAYOUT_WEIGHT_FILL)
        Image(h.auth === AuthMethod.KEY ? $r('app.media.ic_key') : $r('app.media.ic_shield'))
          .width($r('app.float.icon_size_small'))
          .height($r('app.float.icon_size_small'))
          .fillColor($r('app.color.icon_muted'))
        IconButton({
          icon: $r('app.media.ic_more'), label: $r('app.string.action_more'),
          buttonSize: this.touch ? $r('app.float.icon_button_size_touch') : $r('app.float.icon_button_size')
        })
          .bindMenu(this.hostMenu(h))
      }
      .width(UiConst.FULL)
    }
    .attributeModifier(this.card)
    .width(UiConst.FULL)
    .padding($r('app.float.space_m'))
    .clickEffect({ level: ClickEffectLevel.LIGHT })
    .onClick(() => this.open(h))
    .gesture(LongPressGesture().onAction(() => this.edit(h.id)))
    .accessibilityText(h.name + ', ' + hostAddress(h))
  }

  @Builder
  keyCard() {
    Column({ space: $r('app.float.space_s') }) {
      Row({ space: $r('app.float.space_m') }) {
        IconTile({ icon: $r('app.media.ic_key'), tint: $r('app.color.key_tint'), tileBg: $r('app.color.key_tile_bg') })
        Column({ space: $r('app.float.space_xxs') }) {
          Text($r('app.string.remote_key_title'))
            .fontSize($r('app.float.font_m'))
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
          Text(this.store.publicKey.length > 0 ? $r('app.string.remote_key_ready') : $r('app.string.remote_key_none'))
            .fontSize($r('app.float.font_xs'))
            .fontColor($r('app.color.text_secondary'))
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(UiConst.LAYOUT_WEIGHT_FILL)
      }
      .width(UiConst.FULL)
      if (this.store.publicKey.length > 0) {
        Text(this.store.publicKey)
          .fontSize($r('app.float.font_xxs'))
          .fontFamily(MONO_FONT)
          .fontColor($r('app.color.code_text'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width(UiConst.FULL)
          .padding($r('app.float.space_s'))
          .backgroundColor($r('app.color.code_bg'))
          .borderRadius($r('app.float.radius_s'))
          .copyOption(CopyOptions.LocalDevice)
        Text($r('app.string.remote_key_hint'))
          .fontSize($r('app.float.font_xs'))
          .fontColor($r('app.color.text_muted'))
          .width(UiConst.FULL)
      }
      Row({ space: $r('app.float.space_s') }) {
        if (this.store.publicKey.length > 0) {
          ActionButton({
            text: $r('app.string.remote_key_copy'), icon: $r('app.media.ic_copy'), kind: ActionStyle.PRIMARY,
            onTap: () => copyText(this.store.publicKey, Strings.get('remote_key_copied'))
          })
        } else {
          ActionButton({
            text: $r('app.string.remote_key_generate'), icon: $r('app.media.ic_key'), kind: ActionStyle.PRIMARY,
            onTap: () => remoteHosts.generateKey()
          })
        }
        ActionButton({
          text: $r('app.string.remote_key_import'), kind: ActionStyle.SECONDARY, onTap: () => this.importKey()
        })
      }
    }
    .attributeModifier(this.card)
    .width(UiConst.FULL)
    .padding($r('app.float.space_m'))
  }

  private async importKey(): Promise<void> {
    if (remoteHosts.publicKey.length > 0) {
      const ok = await dialogs.confirm(Strings.get('remote_key_replace_title'), Strings.get('remote_key_replace_message'), [
        { label: $r('app.string.action_cancel'), role: ButtonRole.NORMAL },
        { label: $r('app.string.remote_key_replace'), role: ButtonRole.DANGER }
      ]);
      if (ok !== 1) {
        return;
      }
    }
    const text = await dialogs.prompt($r('app.string.remote_key_import'), $r('app.string.remote_key_import_placeholder'), '',
      { label: $r('app.string.remote_key_import_ok'), role: ButtonRole.PRIMARY },
      { label: $r('app.string.action_cancel'), role: ButtonRole.NORMAL });
    if (text === null || text.length === 0) {
      return;
    }
    try {
      remoteHosts.importKey(text);
      toasts.info(Strings.get('remote_key_imported'));
    } catch (e) {
      toasts.error((e as Error).message);
    }
  }

  build() {
    Scroll() {
      Column({ space: $r('app.float.space_m') }) {
        Row({ space: $r('app.float.space_s') }) {
          Text($r('app.string.remote_intro'))
            .fontSize($r('app.float.font_s'))
            .fontColor($r('app.color.text_secondary'))
            .layoutWeight(UiConst.LAYOUT_WEIGHT_FILL)
          ActionButton({
            text: $r('app.string.remote_add'), icon: $r('app.media.ic_add'), kind: ActionStyle.PRIMARY,
            onTap: () => this.edit('')
          })
        }
        .width(UiConst.FULL)
        if (this.store.hosts.length === 0) {
          EmptyState({
            icon: $r('app.media.ic_computer'), title: $r('app.string.remote_empty_title'),
            message: $r('app.string.remote_empty_message')
          })
            .width(UiConst.FULL)
        }
        ForEach(this.store.sorted(), (h: RemoteHost) => {
          this.hostCard(h)
        }, (h: RemoteHost) => h.id + ':' + h.name + ':' + h.host + ':' + h.port + ':' + h.username + ':' + h.jumpHostId)
        this.keyCard()
      }
      .width(UiConst.FULL)
      .padding({ left: this.touch ? $r('app.float.space_l') : $r('app.float.space_xl'),
        right: this.touch ? $r('app.float.space_l') : $r('app.float.space_xl'), bottom: $r('app.float.space_xl') })
    }
    .width(UiConst.FULL)
    .height(UiConst.FULL)
    .align(Alignment.Top)
    .scrollBar(BarState.Auto)
    .edgeEffect(EdgeEffect.Spring)
  }
}
