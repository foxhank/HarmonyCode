import { Strings } from '../../core/common/Strings';
import { RemoteConnection, RemoteEnv, RemoteSecrets } from '../../core/remote/RemoteConnection';
import { AuthMethod, RemoteHost } from '../../core/remote/RemoteHost';
import { UserKey } from '../../core/remote/ssh/SshKeys';
import { ActionButton, ActionStyle } from '../../components/ActionButton';
import { InputModifier } from '../../components/Modifiers';
import { PageHeader } from '../../components/PageHeader';
import { SegmentedControl, SegmentOption } from '../../components/SegmentedControl';
import { ElevatedCardModifier, StatusDot } from '../../components/Surface';
import { UiConst } from '../../components/UiConst';
import { appNav } from '../app/AppNavigation';
import { toasts } from '../dialogs/ToastModel';
import { copyText } from './RemoteHostsView';
import { RemoteHostsStore, remoteHosts } from './RemoteHostsStore';
import { RemoteServices } from './RemoteServices';

const PORT_MAX: number = 65535;
const NO_JUMP: string = '';

/** Secrets for a connection test, before anything is saved. */
class DraftSecrets implements RemoteSecrets {
  private pw: string;

  constructor(pw: string) {
    this.pw = pw;
  }

  password(hostId: string): string {
    return this.pw;
  }

  userKey(): UserKey | null {
    return remoteHosts.userKey();
  }
}

class TestState {
  static readonly NONE: string = 'none';
  static readonly RUNNING: string = 'running';
  static readonly OK: string = 'ok';
  static readonly FAILED: string = 'failed';
}

/** Add or edit a computer: address, login, jump host and start folder, with a connection test. */
@ComponentV2
export struct HostEditorPage {
  @Local hostId: string = '';
  @Local name: string = '';
  @Local host: string = '';
  @Local port: string = '22';
  @Local username: string = '';
  @Local auth: string = AuthMethod.KEY;
  @Local password: string = '';
  @Local hasStoredPassword: boolean = false;
  @Local jumpHostId: string = NO_JUMP;
  @Local startDir: string = '';
  @Local error: string = '';
  @Local test: string = TestState.NONE;
  @Local testResult: string = '';
  @Local store: RemoteHostsStore = remoteHosts;
  private inputStyle: InputModifier = new InputModifier();
  private card: ElevatedCardModifier = new ElevatedCardModifier();

  private load(id: string): void {
    const h = remoteHosts.get(id);
    if (h === undefined) {
      return;
    }
    this.hostId = h.id;
    this.name = h.name;
    this.host = h.host;
    this.port = h.port.toString();
    this.username = h.username;
    this.auth = h.auth;
    this.jumpHostId = h.jumpHostId;
    this.startDir = h.startDir;
    this.hasStoredPassword = remoteHosts.hasPassword(h.id);
  }

  private authOptions(): SegmentOption[] {
    return [
      { value: AuthMethod.KEY, label: $r('app.string.remote_auth_key') },
      { value: AuthMethod.PASSWORD, label: $r('app.string.remote_auth_password') },
    ];
  }

  private jumpOptions(): SelectOption[] {
    const out: SelectOption[] = [{ value: Strings.get('remote_jump_none') }];
    for (const h of this.jumpChoices()) {
      out.push({ value: h.name });
    }
    return out;
  }

  private jumpChoices(): RemoteHost[] {
    return remoteHosts.sorted().filter((h: RemoteHost) => h.id !== this.hostId && h.jumpHostId !== this.hostId);
  }

  /** The form as a host, or null (with `error` set) when it is invalid. */
  private draft(): RemoteHost | null {
    const port = Number(this.port.trim());
    if (this.host.trim().length === 0) {
      this.error = Strings.get('remote_err_host');
      return null;
    }
    if (this.username.trim().length === 0) {
      this.error = Strings.get('remote_err_user');
      return null;
    }
    if (!Number.isInteger(port) || port < 1 || port > PORT_MAX) {
      this.error = Strings.get('remote_err_port');
      return null;
    }
    this.error = '';
    const base = this.hostId.length > 0 ? remoteHosts.get(this.hostId) : undefined;
    return {
      id: this.hostId, name: this.name, host: this.host.trim(), port: port, username: this.username.trim(), auth: this.auth,
      jumpHostId: this.jumpHostId, startDir: this.startDir, lastUsed: base !== undefined ? base.lastUsed : 0
    };
  }

  private passwordForTest(): string {
    if (this.password.length > 0) {
      return this.password;
    }
    return this.hostId.length > 0 ? remoteHosts.password(this.hostId) : '';
  }

  private async runTest(): Promise<void> {
    const h = this.draft();
    if (h === null) {
      return;
    }
    if (h.id.length === 0) {
      h.id = 'draft';
    }
    this.test = TestState.RUNNING;
    this.testResult = '';
    const env: RemoteEnv = RemoteServices.env();
    env.secrets = new DraftSecrets(this.passwordForTest());
    const conn = new RemoteConnection(h, env);
    try {
      await conn.connect();
      const p = conn.platform;
      this.testResult = p !== null ? Strings.get('remote_test_ok', p.release.length > 0 ? p.release : p.os,
        p.hostname) : Strings.get('remote_test_ok_plain');
      this.test = TestState.OK;
    } catch (e) {
      this.testResult = (e as Error).message;
      this.test = TestState.FAILED;
    } finally {
      conn.close();
    }
  }

  private save(): void {
    const h = this.draft();
    if (h === null) {
      return;
    }
    const saved = remoteHosts.upsert(h);
    if (this.auth === AuthMethod.PASSWORD && this.password.length > 0) {
      remoteHosts.setPassword(saved.id, this.password);
    }
    toasts.info(Strings.get('remote_saved', saved.name));
    appNav.pop();
  }

  @Builder
  field(label: ResourceStr, value: string, placeholder: ResourceStr, type: InputType, onChange: (v: string) => void) {
    Column({ space: $r('app.float.space_xs') }) {
      Text(label)
        .fontSize($r('app.float.font_s'))
        .fontColor($r('app.color.text_secondary'))
        .width(UiConst.FULL)
      TextInput({ text: value, placeholder: placeholder })
        .attributeModifier(this.inputStyle)
        .type(type)
        .width(UiConst.FULL)
        .onChange(onChange)
    }
    .width(UiConst.FULL)
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
  addressFields() {
    this.field($r('app.string.remote_field_name'), this.name, $r('app.string.remote_field_name_placeholder'),
      InputType.Normal, (v: string) => {
        this.name = v;
      })
    Row({ space: $r('app.float.space_s') }) {
      Column() {
        this.field($r('app.string.remote_field_host'), this.host, $r('app.string.remote_field_host_placeholder'),
          InputType.URL, (v: string) => {
            this.host = v;
          })
      }
      .layoutWeight(UiConst.LAYOUT_WEIGHT_FILL)
      Column() {
        this.field($r('app.string.remote_field_port'), this.port, '22', InputType.Number, (v: string) => {
          this.port = v;
        })
      }
      .width($r('app.float.port_field_width'))
    }
    .width(UiConst.FULL)
    .alignItems(VerticalAlign.Top)
    this.field($r('app.string.remote_field_user'), this.username, $r('app.string.remote_field_user_placeholder'),
      InputType.Normal, (v: string) => {
        this.username = v;
      })
  }

  @Builder
  loginFields() {
    SegmentedControl({
      options: this.authOptions(), selected: this.auth, onSelect: (v: string) => {
        this.auth = v;
      }
    })
    if (this.auth === AuthMethod.PASSWORD) {
      this.field($r('app.string.remote_field_password'), this.password,
        this.hasStoredPassword ? $r('app.string.remote_password_saved') : $r('app.string.remote_field_password_placeholder'),
        InputType.Password, (v: string) => {
          this.password = v;
        })
      Text($r('app.string.remote_password_hint'))
        .fontSize($r('app.float.font_xs'))
        .fontColor($r('app.color.text_muted'))
        .width(UiConst.FULL)
    } else if (this.store.publicKey.length > 0) {
      Text($r('app.string.remote_key_install'))
        .fontSize($r('app.float.font_xs'))
        .fontColor($r('app.color.text_secondary'))
        .width(UiConst.FULL)
      Text(this.store.publicKey)
        .fontSize($r('app.float.font_xxs'))
        .fontColor($r('app.color.code_text'))
        .width(UiConst.FULL)
        .padding($r('app.float.space_s'))
        .backgroundColor($r('app.color.code_bg'))
        .borderRadius($r('app.float.radius_s'))
        .copyOption(CopyOptions.LocalDevice)
      ActionButton({
        text: $r('app.string.remote_key_copy'), icon: $r('app.media.ic_copy'), kind: ActionStyle.SECONDARY,
        onTap: () => copyText(this.store.publicKey, Strings.get('remote_key_copied'))
      })
    } else {
      Text($r('app.string.remote_key_none'))
        .fontSize($r('app.float.font_xs'))
        .fontColor($r('app.color.text_secondary'))
        .width(UiConst.FULL)
      ActionButton({
        text: $r('app.string.remote_key_generate'), icon: $r('app.media.ic_key'), kind: ActionStyle.PRIMARY,
        onTap: () => remoteHosts.generateKey()
      })
    }
  }

  @Builder
  advancedFields() {
    Column({ space: $r('app.float.space_xs') }) {
      Text($r('app.string.remote_field_jump'))
        .fontSize($r('app.float.font_s'))
        .fontColor($r('app.color.text_secondary'))
        .width(UiConst.FULL)
      Select(this.jumpOptions())
        .selected(Math.max(0, this.jumpChoices().findIndex((h: RemoteHost) => h.id === this.jumpHostId) + 1))
        .value(this.jumpHostId.length === 0 ? Strings.get('remote_jump_none') :
          (remoteHosts.get(this.jumpHostId)?.name ?? Strings.get('remote_jump_none')))
        .font({ size: $r('app.float.font_s') })
        .onSelect((index: number) => {
          const choices = this.jumpChoices();
          this.jumpHostId = index === 0 || index > choices.length ? NO_JUMP : choices[index - 1].id;
        })
      Text($r('app.string.remote_jump_hint'))
        .fontSize($r('app.float.font_xs'))
        .fontColor($r('app.color.text_muted'))
        .width(UiConst.FULL)
    }
    .width(UiConst.FULL)
    this.field($r('app.string.remote_field_dir'), this.startDir, $r('app.string.remote_field_dir_placeholder'),
      InputType.Normal, (v: string) => {
        this.startDir = v;
      })
  }

  @Builder
  testRow() {
    Column({ space: $r('app.float.space_s') }) {
      Row({ space: $r('app.float.space_s') }) {
        ActionButton({
          text: $r('app.string.remote_test'), kind: ActionStyle.SECONDARY, isEnabled: this.test !== TestState.RUNNING,
          onTap: () => this.runTest()
        })
        if (this.test === TestState.RUNNING) {
          LoadingProgress()
            .width($r('app.float.icon_size'))
            .height($r('app.float.icon_size'))
            .color($r('app.color.accent'))
        } else if (this.test !== TestState.NONE) {
          StatusDot({ color: this.test === TestState.OK ? $r('app.color.status_online') : $r('app.color.danger') })
        }
      }
      if (this.testResult.length > 0) {
        Text(this.testResult)
          .fontSize($r('app.float.font_xs'))
          .fontColor(this.test === TestState.OK ? $r('app.color.text_secondary') : $r('app.color.danger'))
          .width(UiConst.FULL)
          .copyOption(CopyOptions.LocalDevice)
      }
    }
    .width(UiConst.FULL)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  trailing() {
    ActionButton({ text: $r('app.string.action_save'), kind: ActionStyle.PRIMARY, onTap: () => this.save() })
  }

  build() {
    NavDestination() {
      Column() {
        PageHeader({
          title: this.hostId.length > 0 ? $r('app.string.remote_edit_title') : $r('app.string.remote_add_title'),
          onBack: () => appNav.pop()
        }) {
          this.trailing()
        }
        Scroll() {
          Column({ space: $r('app.float.space_l') }) {
            Column({ space: $r('app.float.space_m') }) {
              this.sectionTitle($r('app.string.remote_section_address'))
              this.addressFields()
            }
            .attributeModifier(this.card)
            .width(UiConst.FULL)
            .padding($r('app.float.space_l'))
            Column({ space: $r('app.float.space_m') }) {
              this.sectionTitle($r('app.string.remote_section_login'))
              this.loginFields()
            }
            .attributeModifier(this.card)
            .width(UiConst.FULL)
            .padding($r('app.float.space_l'))
            Column({ space: $r('app.float.space_m') }) {
              this.sectionTitle($r('app.string.remote_section_advanced'))
              this.advancedFields()
            }
            .attributeModifier(this.card)
            .width(UiConst.FULL)
            .padding($r('app.float.space_l'))
            this.testRow()
            if (this.error.length > 0) {
              Text(this.error)
                .fontSize($r('app.float.font_s'))
                .fontColor($r('app.color.danger'))
                .width(UiConst.FULL)
            }
          }
          .width(UiConst.FULL)
          .constraintSize({ maxWidth: $r('app.float.form_max_width') })
          .padding({ left: $r('app.float.space_l'), right: $r('app.float.space_l'), bottom: $r('app.float.space_xl') })
        }
        .layoutWeight(UiConst.LAYOUT_WEIGHT_FILL)
        .align(Alignment.Top)
        .edgeEffect(EdgeEffect.Spring)
      }
      .width(UiConst.FULL)
      .height(UiConst.FULL)
    }
    .hideTitleBar(true)
    .backgroundColor($r('app.color.app_bg'))
    .onReady((ctx: NavDestinationContext) => {
      const id = ctx.pathInfo.param as string;
      if (typeof id === 'string' && id.length > 0) {
        this.load(id);
      }
    })
  }
}
