import { FsEntry } from '../../core/agent/AgentFs';
import { PathUtil } from '../../core/fs/PathUtil';
import { EmptyState } from '../../components/EmptyState';
import { MONO_FONT } from '../../components/Fonts';
import { IconButton } from '../../components/IconButton';
import { UiConst } from '../../components/UiConst';
import { RemoteDoc, RemoteFilesModel } from './RemoteFilesModel';

const KB: number = 1024;

function sizeLabel(bytes: number): string {
  if (bytes < KB) {
    return bytes + ' B';
  }
  if (bytes < KB * KB) {
    return (bytes / KB).toFixed(1) + ' KB';
  }
  return (bytes / KB / KB).toFixed(1) + ' MB';
}

/** Files on the remote computer: breadcrumb, folder listing, and a plain text editor. */
@ComponentV2
export struct RemoteFilesView {
  @Param @Require model: RemoteFilesModel;
  @Param touch: boolean = true;

  private buttonSize(): Resource {
    return this.touch ? $r('app.float.icon_button_size_touch') : $r('app.float.icon_button_size');
  }

  @Builder
  folderBar() {
    Row({ space: $r('app.float.space_xxs') }) {
      IconButton({ icon: $r('app.media.ic_arrow_up'), label: $r('app.string.remote_files_up'),
        buttonSize: this.buttonSize(), isEnabled: this.model.dir !== '/', onTap: () => this.model.up() })
      Scroll() {
        Row({ space: $r('app.float.space_xxs') }) {
          Text('/')
            .fontSize($r('app.float.font_s'))
            .fontColor($r('app.color.text_link'))
            .onClick(() => this.model.open('/'))
          ForEach(this.model.crumbs(), (c: string, i: number) => {
            Text(c + '/')
              .fontSize($r('app.float.font_s'))
              .fontColor(i === this.model.crumbs().length - 1 ? $r('app.color.text_primary') : $r('app.color.text_link'))
              .fontWeight(i === this.model.crumbs().length - 1 ? FontWeight.Medium : FontWeight.Normal)
              .onClick(() => this.model.open(this.model.crumbPath(i)))
          }, (c: string, i: number) => i + ':' + c)
        }
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .layoutWeight(UiConst.LAYOUT_WEIGHT_FILL)
      IconButton({ icon: $r('app.media.ic_new_file'), label: $r('app.string.remote_files_new_file'),
        buttonSize: this.buttonSize(), onTap: () => this.model.create(false) })
      IconButton({ icon: $r('app.media.ic_new_folder'), label: $r('app.string.remote_files_new_folder'),
        buttonSize: this.buttonSize(), onTap: () => this.model.create(true) })
      IconButton({ icon: $r('app.media.ic_refresh'), label: $r('app.string.action_refresh'),
        buttonSize: this.buttonSize(), onTap: () => this.model.refresh() })
    }
    .width(UiConst.FULL)
    .height(this.touch ? $r('app.float.titlebar_height_touch') : $r('app.float.titlebar_height'))
    .padding({ left: $r('app.float.space_xs'), right: $r('app.float.space_xs') })
  }

  @Builder
  entryMenu(e: FsEntry) {
    Menu() {
      MenuItem({ content: $r('app.string.action_open') }).onClick(() => this.model.tap(e))
      MenuItem({ content: $r('app.string.action_delete') }).onClick(() => this.model.remove(e))
    }
  }

  @Builder
  row(e: FsEntry) {
    Row({ space: $r('app.float.space_m') }) {
      Image(e.isDir ? $r('app.media.ic_folder') : $r('app.media.ic_file'))
        .width($r('app.float.icon_size'))
        .height($r('app.float.icon_size'))
        .fillColor(e.isDir ? $r('app.color.folder_icon') : $r('app.color.icon'))
      Text(e.name)
        .fontSize($r('app.float.font_m'))
        .fontColor($r('app.color.text_primary'))
        .maxLines(UiConst.MAX_LINES_TITLE)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(UiConst.LAYOUT_WEIGHT_FILL)
      if (!e.isDir) {
        Text(sizeLabel(e.size))
          .fontSize($r('app.float.font_xs'))
          .fontColor($r('app.color.text_muted'))
      }
    }
    .width(UiConst.FULL)
    .height(this.touch ? $r('app.float.list_row_touch') : $r('app.float.list_row'))
    .padding({ left: $r('app.float.space_l'), right: $r('app.float.space_l') })
    .clickEffect({ level: ClickEffectLevel.LIGHT })
    .onClick(() => this.model.tap(e))
    .bindContextMenu(this.entryMenu(e), ResponseType.LongPress)
  }

  @Builder
  editor(doc: RemoteDoc) {
    Column() {
      Row({ space: $r('app.float.space_xs') }) {
        IconButton({ icon: $r('app.media.ic_arrow_back'), label: $r('app.string.action_close'),
          buttonSize: this.buttonSize(), onTap: () => this.model.closeDoc() })
        Column() {
          Text(PathUtil.baseName(doc.path) + (doc.dirty ? ' •' : ''))
            .fontSize($r('app.float.font_m'))
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .maxLines(UiConst.MAX_LINES_TITLE)
          Text(PathUtil.dirName(doc.path))
            .fontSize($r('app.float.font_xxs'))
            .fontColor($r('app.color.text_muted'))
            .maxLines(UiConst.MAX_LINES_TITLE)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(UiConst.LAYOUT_WEIGHT_FILL)
        if (doc.saving) {
          LoadingProgress()
            .width($r('app.float.icon_size'))
            .height($r('app.float.icon_size'))
            .color($r('app.color.accent'))
        }
        IconButton({ icon: $r('app.media.ic_check'), label: $r('app.string.action_save'), buttonSize: this.buttonSize(),
          color: $r('app.color.accent'), isEnabled: doc.dirty && !doc.saving, onTap: () => this.model.save() })
      }
      .width(UiConst.FULL)
      .height(this.touch ? $r('app.float.titlebar_height_touch') : $r('app.float.titlebar_height'))
      .padding({ left: $r('app.float.space_xs'), right: $r('app.float.space_xs') })
      TextArea({ text: doc.text })
        .fontFamily(MONO_FONT)
        .fontSize($r('app.float.font_s'))
        .fontColor($r('app.color.code_text'))
        .backgroundColor($r('app.color.code_bg'))
        .borderRadius(0)
        .caretColor($r('app.color.accent'))
        .width(UiConst.FULL)
        .layoutWeight(UiConst.LAYOUT_WEIGHT_FILL)
        .enableKeyboardOnFocus(true)
        .onChange((v: string) => {
          doc.text = v;
        })
    }
    .width(UiConst.FULL)
    .height(UiConst.FULL)
  }

  build() {
    Column() {
      if (this.model.doc !== null) {
        this.editor(this.model.doc as RemoteDoc)
      } else {
        this.folderBar()
        Divider().color($r('app.color.border'))
        if (this.model.error.length > 0) {
          EmptyState({ icon: $r('app.media.ic_info'), title: $r('app.string.remote_files_error'),
            message: this.model.error })
            .layoutWeight(UiConst.LAYOUT_WEIGHT_FILL)
        } else if (this.model.loading && this.model.entries.length === 0) {
          LoadingProgress()
            .width($r('app.float.empty_icon_size'))
            .height($r('app.float.empty_icon_size'))
            .color($r('app.color.accent'))
            .layoutWeight(UiConst.LAYOUT_WEIGHT_FILL)
        } else {
          List() {
            ForEach(this.model.entries, (e: FsEntry) => {
              ListItem() {
                this.row(e)
              }
            }, (e: FsEntry) => e.path + ':' + e.size)
          }
          .width(UiConst.FULL)
          .layoutWeight(UiConst.LAYOUT_WEIGHT_FILL)
          .scrollBar(BarState.Auto)
          .edgeEffect(EdgeEffect.Spring)
          .divider({ strokeWidth: $r('app.float.border_width'), color: $r('app.color.divider_soft'),
            startMargin: $r('app.float.list_divider_inset') })
        }
      }
    }
    .width(UiConst.FULL)
    .height(UiConst.FULL)
    .backgroundColor($r('app.color.panel_bg'))
  }
}
